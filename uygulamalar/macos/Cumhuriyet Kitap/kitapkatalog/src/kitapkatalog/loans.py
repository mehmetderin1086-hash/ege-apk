"""Ödünç verme/iade servisi: kurallar, gecikme engeli, yarış güvenli nüsha seçimi."""

from __future__ import annotations

import json
import sqlite3
import uuid
from collections.abc import Iterable, Mapping
from dataclasses import asdict, dataclass, replace
from datetime import UTC, date, datetime, timedelta
from typing import Any

from kitapkatalog.codes import compact_code, isbn_candidate, resolve_catalog_code
from kitapkatalog.database import Database, DatabaseError, StateConflictError
from kitapkatalog.notifications import Notifications
from kitapkatalog.settings import AppSettings

_PENALTY_LOOKBACK_DAYS = 730


def _now_dt(now: datetime | None) -> datetime:
    # Yerel saat: gün sınırı (son teslim/gecikme) kullanıcının gününe göre
    # hesaplanır; UTC kullanmak TR'de 00:00-03:00 arasında bir gün kaydırırdı.
    return now if now is not None else datetime.now(UTC).astimezone()


def _stamp(now: datetime) -> str:
    return now.isoformat(timespec="microseconds")


def _date_of(value: str) -> date:
    return date.fromisoformat(value[:10])


def _academic_period_for(value: date) -> str:
    """Return the Turkish school-year label containing ``value``."""

    first_year = value.year if value.month >= 9 else value.year - 1
    return f"{first_year:04d}-{first_year + 1:04d}"


def _canonical_json(value: Mapping[str, Any]) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


@dataclass(frozen=True, slots=True)
class LoanRecord:
    id: int
    copy_id: int | None
    member_id: int
    edition_id: int | None
    title_snapshot: str
    inventory_code_snapshot: str | None
    loaned_at: str
    due_at: str
    returned_at: str | None
    renewal_count: int
    notes: str | None
    member_name: str = ""
    member_class: str | None = None
    member_number: str | None = None
    member_type: str = "student"
    academic_period: str | None = None
    snapshot_source: str = "checkout"
    hold_ready: dict[str, Any] | None = None

    def is_overdue(self, now: datetime) -> bool:
        return self.returned_at is None and self.due_at < now.date().isoformat()

    def days_overdue(self, now: datetime) -> int:
        if self.returned_at is None:
            late = (now.date() - _date_of(self.due_at)).days
        else:
            late = (_date_of(self.returned_at) - _date_of(self.due_at)).days
        return max(0, late)

    def to_dict(self, now: datetime | None = None) -> dict[str, Any]:
        now = _now_dt(now)
        return {
            "id": self.id,
            "copy_id": self.copy_id,
            "member_id": self.member_id,
            "edition_id": self.edition_id,
            "title": self.title_snapshot,
            "inventory_code": self.inventory_code_snapshot,
            "loaned_at": self.loaned_at,
            "due_at": self.due_at,
            "returned_at": self.returned_at,
            "renewal_count": self.renewal_count,
            "notes": self.notes,
            "member_name": self.member_name,
            "member_class": self.member_class,
            "member_number": self.member_number,
            "member_type": self.member_type,
            "academic_period": self.academic_period,
            "snapshot_source": self.snapshot_source,
            "overdue": self.is_overdue(now),
            "days_overdue": self.days_overdue(now),
            "hold_ready": self.hold_ready,
        }


@dataclass(frozen=True, slots=True)
class HoldRecord:
    """Rezervasyon: bir üyenin, o an rafta uygun nüshası olmayan bir baskı için
    sıraya girmesi. ``ready`` durumu iade sonrası ya da sıradakine devirle
    üretilir; ``ready_copy_id`` o anki teslim için ayrılan nüshayı gösterir."""

    id: int
    edition_id: int
    member_id: int
    status: str
    created_at: str
    ready_at: str | None = None
    ready_copy_id: int | None = None
    expires_at: str | None = None
    title: str = ""
    member_name: str = ""
    school_number: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "edition_id": self.edition_id,
            "member_id": self.member_id,
            "status": self.status,
            "created_at": self.created_at,
            "ready_at": self.ready_at,
            "ready_copy_id": self.ready_copy_id,
            "expires_at": self.expires_at,
            "title": self.title,
            "member_name": self.member_name,
            "school_number": self.school_number,
        }


@dataclass(frozen=True, slots=True)
class MemberBlockRecord:
    """Üye yasağı: elle konan bekletme ya da geç-iade cezasını söndüren af."""

    id: int
    member_id: int
    kind: str
    start_date: str
    end_date: str | None
    reason: str | None
    created_at: str
    lifted_at: str | None = None
    lift_reason: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "member_id": self.member_id,
            "kind": self.kind,
            "start_date": self.start_date,
            "end_date": self.end_date,
            "reason": self.reason,
            "created_at": self.created_at,
            "lifted_at": self.lifted_at,
            "lift_reason": self.lift_reason,
            "active": self.lifted_at is None,
        }


_LOAN_SELECT = """
SELECT l.*,
       l.member_name_snapshot AS member_name,
       l.member_class_snapshot AS member_class,
       l.member_number_snapshot AS member_number,
       l.member_type_snapshot AS member_type,
       l.academic_period_snapshot AS academic_period
FROM loan AS l
"""


class Loans:
    def __init__(self, database: Database, settings: AppSettings) -> None:
        self.db = database
        self.settings = settings

    @staticmethod
    def _request_id(value: str | None) -> str:
        """Normalize a client id or generate a collision-safe legacy id.

        Existing CLI/Qt integrations predate idempotency keys, so an omitted
        value intentionally means a new command. Web clients can provide a UUID
        and safely retry the same command.
        """

        if value is None:
            return f"legacy-{uuid.uuid4().hex}"
        normalized = str(value).strip()
        if not 8 <= len(normalized) <= 200:
            raise ValueError("request_id 8-200 karakter olmalıdır")
        return normalized

    def _replay_event(
        self,
        connection: sqlite3.Connection,
        *,
        request_id: str,
        event_type: str,
        request_json: str,
    ) -> LoanRecord | None:
        row = connection.execute(
            "SELECT event_type, request_json, result_json FROM circulation_event "
            "WHERE request_id = ?",
            (request_id,),
        ).fetchone()
        if row is None:
            return None
        if row["event_type"] != event_type or row["request_json"] != request_json:
            raise StateConflictError(
                "Bu request_id daha önce farklı bir dolaşım işlemi için kullanılmış"
            )
        try:
            payload = json.loads(row["result_json"])
            if not isinstance(payload, dict):
                raise TypeError("event result is not an object")
            return self._record(payload)
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
            raise DatabaseError("Dolaşım olay günlüğündeki sonuç okunamadı") from exc

    @staticmethod
    def _write_event(
        connection: sqlite3.Connection,
        *,
        request_id: str,
        event_type: str,
        request_json: str,
        record: LoanRecord,
        occurred_at: str,
        now: datetime,
    ) -> None:
        connection.execute(
            """
            INSERT INTO circulation_event(
                request_id, event_type, loan_id, copy_id, member_id, edition_id,
                request_json, result_json, occurred_at, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                request_id,
                event_type,
                record.id,
                record.copy_id,
                record.member_id,
                record.edition_id,
                request_json,
                _canonical_json(asdict(record)),
                occurred_at,
                _stamp(now),
            ),
        )

    @staticmethod
    def _get_in_connection(
        connection: sqlite3.Connection, loan_id: int
    ) -> LoanRecord | None:
        row = connection.execute(_LOAN_SELECT + " WHERE l.id = ?", (loan_id,)).fetchone()
        return Loans._record(row) if row is not None else None

    # ── Verme ───────────────────────────────────────────────────────

    def checkout(
        self,
        member_id: int,
        *,
        edition_id: int | None = None,
        isbn: str | None = None,
        copy_id: int | None = None,
        code: str | None = None,
        now: datetime | None = None,
        request_id: str | None = None,
    ) -> LoanRecord:
        now_dt = _now_dt(now)
        today = now_dt.date()
        isbn = (isbn or "").strip() or None
        code = (code or "").strip() or None
        selectors = (
            edition_id is not None,
            isbn is not None,
            copy_id is not None,
            code is not None,
        )
        if sum(selectors) != 1:
            raise ValueError(
                "edition_id, isbn, copy_id veya code alanlarından tam olarak biri gerekli"
            )
        request_id = self._request_id(request_id)
        request_json = _canonical_json(
            {
                "member_id": int(member_id),
                "edition_id": int(edition_id) if edition_id is not None else None,
                "isbn": isbn,
                "copy_id": int(copy_id) if copy_id is not None else None,
                "code": code,
            }
        )
        with self.db.transaction(immediate=True) as connection:
            replay = self._replay_event(
                connection, request_id=request_id, event_type="checkout",
                request_json=request_json,
            )
            if replay is not None:
                return replay
            member = connection.execute(
                "SELECT * FROM member WHERE id = ?", (member_id,)
            ).fetchone()
            if member is None:
                raise KeyError("Üye bulunamadı")
            if not member["is_active"]:
                raise StateConflictError("Üye pasif durumda; ödünç verilemez")
            member_type = member["member_type"]
            period_days = self.settings.loan_period_for(member_type)
            limit = self.settings.loan_limit_for(member_type)

            active = connection.execute(
                """
                SELECT COUNT(*) AS count,
                       SUM(CASE WHEN due_at < ? THEN 1 ELSE 0 END) AS overdue
                FROM loan WHERE member_id = ? AND returned_at IS NULL
                """,
                (today.isoformat(), member_id),
            ).fetchone()
            if self.settings.overdue_block and int(active["overdue"] or 0) > 0:
                raise StateConflictError(
                    "Üyenin gecikmiş kitabı var; önce iade alınmalı"
                )
            if int(active["count"]) >= limit:
                raise StateConflictError(f"Üye en fazla {limit} kitap alabilir")
            self._check_penalty(connection, member_id, today)

            # hold_enabled yalnız YENİ rezervasyon açmayı kapatır. Mevcut
            # active/ready rezervasyonların koruması, kapatılması ve devri her
            # zaman çalışır — aksi hâlde ayar kapatıldığı anda ayrılmış nüsha
            # başkasına verilebilir ve açık rezervasyonlar süresiz askıda kalır.
            copy_row = self._pick_copy(
                connection,
                edition_id=edition_id,
                isbn=isbn,
                copy_id=copy_id,
                code=code,
                member_id=member_id,
                hold_enabled=True,
            )
            same_edition = connection.execute(
                """
                SELECT 1 FROM loan
                WHERE member_id = ? AND edition_id = ? AND returned_at IS NULL
                """,
                (member_id, int(copy_row["edition_id"])),
            ).fetchone()
            if same_edition is not None:
                raise StateConflictError(
                    "Bu üyenin aynı baskıdan aktif bir nüshası zaten var"
                )
            title = connection.execute(
                "SELECT title FROM edition WHERE id = ?", (copy_row["edition_id"],)
            ).fetchone()
            due = today + timedelta(days=period_days)
            stamp = _stamp(now_dt)
            try:
                cursor = connection.execute(
                    """
                    INSERT INTO loan(copy_id, member_id, edition_id, title_snapshot,
                                     inventory_code_snapshot, loaned_at, due_at,
                                     member_name_snapshot, member_number_snapshot,
                                     member_class_snapshot, member_type_snapshot,
                                     academic_period_snapshot, snapshot_source,
                                     created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        int(copy_row["id"]),
                        member_id,
                        int(copy_row["edition_id"]),
                        title["title"] if title is not None else "bilinmiyor",
                        copy_row["inventory_code"],
                        stamp,
                        due.isoformat(),
                        f"{member['first_name']} {member['last_name']}".strip(),
                        member["school_number"],
                        member["class_name"],
                        member_type,
                        _academic_period_for(today),
                        "checkout",
                        stamp,
                        stamp,
                    ),
                )
            except sqlite3.IntegrityError as exc:
                raise StateConflictError("Bu nüsha az önce ödünç verildi") from exc
            loan_id = int(cursor.lastrowid)
            # Üyenin bu baskıdaki rezervasyonu HANGİ durumda olursa olsun
            # kapanır: kitabı eline aldı (ayardan bağımsız — bkz. yukarıdaki
            # not). Hazır rezervasyon farklı bir nüshaya bağlıysa o nüsha boşa
            # çıkar ve sıradaki üyeye devredilir — aksi hâlde ayrılan nüsha
            # rafta durduğu hâlde süre dolana dek kimseye verilemezdi.
            hold_row = connection.execute(
                "SELECT id, status, ready_copy_id FROM hold "
                "WHERE member_id = ? AND edition_id = ? "
                "AND status IN ('active', 'ready') "
                "ORDER BY created_at, id LIMIT 1",
                (member_id, int(copy_row["edition_id"])),
            ).fetchone()
            if hold_row is not None:
                connection.execute(
                    "UPDATE hold SET status = 'fulfilled' WHERE id = ?",
                    (hold_row["id"],),
                )
                reserved_copy = int(hold_row["ready_copy_id"] or 0)
                if (
                    hold_row["status"] == "ready"
                    and reserved_copy
                    and reserved_copy != int(copy_row["id"])
                ):
                    self._promote_next_hold(
                        connection,
                        edition_id=int(copy_row["edition_id"]),
                        copy_id=reserved_copy,
                        now_dt=now_dt,
                        stamp=stamp,
                    )
            record = self._get_in_connection(connection, loan_id)
            assert record is not None
            self._write_event(
                connection,
                request_id=request_id,
                event_type="checkout",
                request_json=request_json,
                record=record,
                occurred_at=stamp,
                now=now_dt,
            )
            return record

    _PENALTY_ROWS_SQL = """
        SELECT due_at, returned_at FROM loan
        WHERE member_id = ? AND returned_at IS NOT NULL AND returned_at >= ?
          AND substr(returned_at, 1, 10) > due_at
    """

    # `?, today, today`: start_date <= today <= (end_date ya da sınırsız).
    _WAIVER_SQL = """
        SELECT created_at FROM member_block
        WHERE member_id = ? AND kind = 'auto_overdue_waiver' AND lifted_at IS NULL
          AND start_date <= ? AND (end_date IS NULL OR end_date >= ?)
        ORDER BY created_at DESC
        LIMIT 1
    """
    _MANUAL_BLOCK_SQL = """
        SELECT * FROM member_block
        WHERE member_id = ? AND kind = 'manual' AND lifted_at IS NULL
          AND start_date <= ? AND (end_date IS NULL OR end_date >= ?)
        LIMIT 1
    """

    @staticmethod
    def _rows_after_waiver(rows: Iterable[sqlite3.Row], waiver_row: Any) -> list[sqlite3.Row]:
        """Af, yalnız af ANINDA var olan cezaları söndürür.

        Af verildikten SONRA iade edilen gecikmiş kitapların cezası yaşamaya
        devam eder — aksi hâlde af penceresi bitene kadar işlenen her yeni
        gecikme de sessizce yutulurdu.
        """

        # Tam zaman damgası karşılaştırması (ikisi de _stamp ISO formatı):
        # güne yuvarlamak, af sabah verildiğinde aynı gün öğleden sonra iade
        # edilen yeni gecikmenin cezasını da yanlışlıkla söndürürdü.
        cutoff = str(waiver_row["created_at"])
        return [row for row in rows if str(row["returned_at"]) > cutoff]

    def _penalty_end_from_rows(self, rows: Iterable[sqlite3.Row], today: date) -> date | None:
        per_day = self.settings.overdue_penalty_per_day
        penalty_end = None
        for row in rows:
            late_days = (_date_of(row["returned_at"]) - _date_of(row["due_at"])).days
            end = _date_of(row["returned_at"]) + timedelta(days=late_days * per_day)
            if penalty_end is None or end > penalty_end:
                penalty_end = end
        if penalty_end is not None and penalty_end > today:
            return penalty_end
        return None

    def penalty_end_for(
        self, member_id: int, *, now: datetime | None = None
    ) -> date | None:
        """Üyenin süren geç-iade bekleme cezasının bitiş günü (afla söndürülmüşse None)."""

        today = _now_dt(now).date()
        if self.settings.overdue_penalty_per_day <= 0:
            return None
        since = (today - timedelta(days=_PENALTY_LOOKBACK_DAYS)).isoformat()
        rows = self.db.fetchall(self._PENALTY_ROWS_SQL, (member_id, since))
        penalty_end = self._penalty_end_from_rows(rows, today)
        if penalty_end is None:
            return None
        waived = self.db.fetchone(
            self._WAIVER_SQL, (member_id, today.isoformat(), today.isoformat())
        )
        if waived is None:
            return penalty_end
        return self._penalty_end_from_rows(self._rows_after_waiver(rows, waived), today)

    def _penalty_end_in_connection(
        self, connection: sqlite3.Connection, member_id: int, today: date
    ) -> date | None:
        """Aynı bağlantı/kilit içinde süren cezanın bitişi (af düşülmüş)."""

        if self.settings.overdue_penalty_per_day <= 0:
            return None
        since = (today - timedelta(days=_PENALTY_LOOKBACK_DAYS)).isoformat()
        rows = connection.execute(self._PENALTY_ROWS_SQL, (member_id, since)).fetchall()
        penalty_end = self._penalty_end_from_rows(rows, today)
        if penalty_end is None:
            return None
        waived = connection.execute(
            self._WAIVER_SQL, (member_id, today.isoformat(), today.isoformat())
        ).fetchone()
        if waived is None:
            return penalty_end
        return self._penalty_end_from_rows(self._rows_after_waiver(rows, waived), today)

    def _check_penalty(
        self, connection: sqlite3.Connection, member_id: int, today: date
    ) -> None:
        blocked = connection.execute(
            self._MANUAL_BLOCK_SQL, (member_id, today.isoformat(), today.isoformat())
        ).fetchone()
        if blocked is not None:
            reason = (blocked["reason"] or "").strip() or "gerekçe belirtilmedi"
            raise StateConflictError(f"Üye yasaklı ({reason}); ödünç verilemez")
        penalty_end = self._penalty_end_in_connection(connection, member_id, today)
        if penalty_end is not None:
            raise StateConflictError(
                f"Geç iade nedeniyle {penalty_end.isoformat()} tarihine kadar bekleme süresi var"
            )

    @staticmethod
    def _pick_copy(
        connection: sqlite3.Connection,
        *,
        edition_id: int | None,
        isbn: str | None,
        copy_id: int | None,
        code: str | None = None,
        member_id: int | None = None,
        hold_enabled: bool = False,
    ) -> sqlite3.Row:
        if code and copy_id is None and edition_id is None and isbn is None:
            resolved = resolve_catalog_code(connection, code)
            if resolved.kind == "inventory":
                copy_id = resolved.copy_id
            elif resolved.kind == "isbn":
                edition_id = resolved.edition_id
            else:
                raise KeyError(f"Bu kod katalogda kayıtlı değil: {code}")
        if copy_id is not None:
            row = connection.execute(
                """
                SELECT c.* FROM copy AS c
                WHERE c.id = ? AND c.status = 'active' AND NOT EXISTS(
                    SELECT 1 FROM loan WHERE copy_id = c.id AND returned_at IS NULL
                )
                """,
                (copy_id,),
            ).fetchone()
            if row is None:
                raise StateConflictError("Bu nüsha ödünçte ya da kullanılabilir değil")
            if hold_enabled:
                reserved = connection.execute(
                    "SELECT member_id FROM hold WHERE ready_copy_id = ? AND status = 'ready'",
                    (copy_id,),
                ).fetchone()
                if reserved is not None and (
                    member_id is None or int(reserved["member_id"]) != int(member_id)
                ):
                    raise StateConflictError("Bu nüsha başka bir üye için ayrılmış")
            return row
        if isbn:
            # Açık isbn= parametresi hane sayısına bakılmadan aranır (ISSN gibi
            # ISBN dışı tanımlayıcılar da normalized_value'da yaşar); 10/13
            # hane kapısı yalnız serbest `code` çözümlemesinde uygulanır.
            compact = compact_code(isbn)
            identifier = None
            if compact:
                identifier = connection.execute(
                    "SELECT edition_id FROM identifier WHERE normalized_value = ?",
                    (compact,),
                ).fetchone()
            if identifier is None:
                raise KeyError(f"Bu ISBN katalogda kayıtlı değil: {isbn}")
            edition_id = int(identifier["edition_id"])
        if edition_id is None:
            raise ValueError("edition_id, isbn veya copy_id gerekli")
        if hold_enabled and member_id is not None:
            # Bu üyenin bu baskı için hazır bekleyen rezervasyonu varsa, FIFO
            # sırasını atlayıp doğrudan onun için ayrılmış nüshayı ver.
            own_ready = connection.execute(
                """
                SELECT ready_copy_id FROM hold
                WHERE edition_id = ? AND member_id = ? AND status = 'ready'
                ORDER BY id LIMIT 1
                """,
                (edition_id, member_id),
            ).fetchone()
            if own_ready is not None and own_ready["ready_copy_id"] is not None:
                row = connection.execute(
                    """
                    SELECT c.* FROM copy AS c
                    WHERE c.id = ? AND c.status = 'active' AND NOT EXISTS(
                        SELECT 1 FROM loan WHERE copy_id = c.id AND returned_at IS NULL
                    )
                    """,
                    (own_ready["ready_copy_id"],),
                ).fetchone()
                if row is not None:
                    return row
        exclusion = (
            "AND c.id NOT IN ("
            "SELECT ready_copy_id FROM hold WHERE status = 'ready' AND ready_copy_id IS NOT NULL"
            ")"
            if hold_enabled
            else ""
        )
        row = connection.execute(
            f"""
            SELECT c.* FROM copy AS c
            WHERE c.edition_id = ? AND c.status = 'active' AND NOT EXISTS(
                SELECT 1 FROM loan WHERE copy_id = c.id AND returned_at IS NULL
            ) {exclusion}
            ORDER BY c.id LIMIT 1
            """,
            (edition_id,),
        ).fetchone()
        if row is None:
            exists = connection.execute(
                "SELECT 1 FROM edition WHERE id = ?", (edition_id,)
            ).fetchone()
            if exists is None:
                raise KeyError("Kitap bulunamadı")
            raise StateConflictError("Uygun nüsha yok; tüm nüshalar ödünçte")
        return row

    # ── İade / uzatma ───────────────────────────────────────────────

    def return_loan(
        self,
        loan_id: int,
        *,
        now: datetime | None = None,
        request_id: str | None = None,
    ) -> LoanRecord:
        now_dt = _now_dt(now)
        request_id = self._request_id(request_id)
        request_json = _canonical_json({"loan_id": int(loan_id)})
        with self.db.transaction(immediate=True) as connection:
            replay = self._replay_event(
                connection, request_id=request_id, event_type="return",
                request_json=request_json,
            )
            if replay is not None:
                return replay
            return self._return_in_tx(
                connection,
                loan_id=int(loan_id),
                now_dt=now_dt,
                request_id=request_id,
                request_json=request_json,
            )

    def _return_in_tx(
        self,
        connection: sqlite3.Connection,
        *,
        loan_id: int,
        now_dt: datetime,
        request_id: str,
        request_json: str,
    ) -> LoanRecord:
        row = connection.execute(
            "SELECT returned_at, copy_id, edition_id FROM loan WHERE id = ?", (loan_id,)
        ).fetchone()
        if row is None:
            raise KeyError("Ödünç kaydı bulunamadı")
        if row["returned_at"] is not None:
            raise StateConflictError("Bu kayıt zaten iade edilmiş")
        stamp = _stamp(now_dt)
        connection.execute(
            "UPDATE loan SET returned_at = ?, updated_at = ? WHERE id = ?",
            (stamp, stamp, loan_id),
        )
        hold_ready = None
        # Devir ayardan bağımsız çalışır: hold_enabled kapatılsa bile açık
        # rezervasyonlar iade edildikçe ilerlemeli, süresiz askıda kalmamalı.
        if row["copy_id"] is not None and row["edition_id"] is not None:
            hold_ready = self._promote_next_hold(
                connection,
                edition_id=int(row["edition_id"]),
                copy_id=int(row["copy_id"]),
                now_dt=now_dt,
                stamp=stamp,
            )
        record = self._get_in_connection(connection, loan_id)
        assert record is not None
        if hold_ready is not None:
            record = replace(record, hold_ready=hold_ready)
        self._write_event(
            connection,
            request_id=request_id,
            event_type="return",
            request_json=request_json,
            record=record,
            occurred_at=stamp,
            now=now_dt,
        )
        return record

    def return_by_code(
        self,
        code: str,
        *,
        now: datetime | None = None,
        request_id: str | None = None,
    ) -> LoanRecord:
        code = (code or "").strip()
        if not code:
            raise ValueError("Kod boş olamaz")
        now_dt = _now_dt(now)
        request_id = self._request_id(request_id)
        request_json = _canonical_json({"code": code})
        with self.db.transaction(immediate=True) as connection:
            replay = self._replay_event(
                connection, request_id=request_id, event_type="return",
                request_json=request_json,
            )
            if replay is not None:
                return replay
            # Önce demirbaş: yıl+sıra kodları rakam ayıklanınca 10 haneye düşüp
            # kayıtlı bir ISBN ile çakışabilir; tam eşleşme her zaman kazanır.
            row = connection.execute(
                _LOAN_SELECT
                + """
                WHERE l.returned_at IS NULL AND l.inventory_code_snapshot = ?
                ORDER BY l.due_at LIMIT 1
                """,
                (code,),
            ).fetchone()
            if row is None:
                compact = isbn_candidate(code)
                if compact is not None:
                    row = connection.execute(
                        _LOAN_SELECT
                        + """
                        WHERE l.returned_at IS NULL AND l.edition_id IN (
                            SELECT edition_id FROM identifier WHERE normalized_value = ?
                        )
                        ORDER BY l.due_at LIMIT 1
                        """,
                        (compact,),
                    ).fetchone()
            if row is None:
                raise KeyError(f"Bu koda ait açık ödünç bulunamadı: {code}")
            return self._return_in_tx(
                connection,
                loan_id=int(row["id"]),
                now_dt=now_dt,
                request_id=request_id,
                request_json=request_json,
            )

    def extend(
        self,
        loan_id: int,
        *,
        days: int | None = None,
        now: datetime | None = None,
        request_id: str | None = None,
    ) -> LoanRecord:
        now_dt = _now_dt(now)
        request_id = self._request_id(request_id)
        request_json = _canonical_json(
            {"loan_id": int(loan_id), "days": int(days) if days is not None else None}
        )
        stamp = _stamp(now_dt)
        with self.db.transaction(immediate=True) as connection:
            replay = self._replay_event(
                connection, request_id=request_id, event_type="extend",
                request_json=request_json,
            )
            if replay is not None:
                return replay
            row = connection.execute(
                _LOAN_SELECT + " WHERE l.id = ?", (loan_id,)
            ).fetchone()
            if row is None:
                raise KeyError("Ödünç kaydı bulunamadı")
            if row["returned_at"] is not None:
                raise StateConflictError("İade edilmiş kayıt uzatılamaz")
            limit = self.settings.loan_max_renewals
            if limit > 0 and int(row["renewal_count"]) >= limit:
                raise StateConflictError(f"Uzatma sınırına ulaşıldı (en fazla {limit} kez)")
            extra = days if days else self.settings.loan_period_for(row["member_type"])
            # Gecikmiş kayıt geçmişe uzamasın: taban bugünle son günün geç olanı.
            base = max(now_dt.date(), _date_of(row["due_at"]))
            new_due = base + timedelta(days=int(extra))
            connection.execute(
                """
                UPDATE loan SET due_at = ?, renewal_count = renewal_count + 1,
                                updated_at = ?
                WHERE id = ?
                """,
                (new_due.isoformat(), stamp, loan_id),
            )
            record = self._get_in_connection(connection, loan_id)
            assert record is not None
            self._write_event(
                connection,
                request_id=request_id,
                event_type="extend",
                request_json=request_json,
                record=record,
                occurred_at=stamp,
                now=now_dt,
            )
            return record

    # ── Listeler / istatistik ───────────────────────────────────────

    def get(self, loan_id: int) -> LoanRecord | None:
        row = self.db.fetchone(_LOAN_SELECT + " WHERE l.id = ?", (loan_id,))
        return self._record(row) if row is not None else None

    def list_loans(
        self,
        *,
        status: str = "active",
        q: str = "",
        member_id: int | None = None,
        edition_id: int | None = None,
        limit: int = 50,
        offset: int = 0,
        now: datetime | None = None,
    ) -> tuple[list[LoanRecord], int]:
        now_dt = _now_dt(now)
        where: list[str] = []
        parameters: list[Any] = []
        if status == "active":
            where.append("l.returned_at IS NULL")
        elif status == "overdue":
            where.append("l.returned_at IS NULL AND l.due_at < ?")
            parameters.append(now_dt.date().isoformat())
        elif status == "returned":
            where.append("l.returned_at IS NOT NULL")
        if member_id is not None:
            where.append("l.member_id = ?")
            parameters.append(member_id)
        if edition_id is not None:
            where.append("l.edition_id = ?")
            parameters.append(edition_id)
        clause = f"WHERE {' AND '.join(where)}" if where else ""
        limit = max(1, min(int(limit), 500))
        offset = max(0, int(offset))
        if not q.strip():
            # En sık kullanılan ödünç listesi doğrudan SQL'de sayfalanır;
            # yılların geçmişini Python nesnelerine dönüştürmez.
            with self.db.connection(readonly=True) as connection:
                total = int(
                    connection.execute(
                        f"""
                        SELECT COUNT(*) FROM loan AS l
                        {clause}
                        """,
                        parameters,
                    ).fetchone()[0]
                )
                rows = connection.execute(
                    f"{_LOAN_SELECT} {clause} ORDER BY l.due_at, l.id LIMIT ? OFFSET ?",
                    (*parameters, limit, offset),
                ).fetchall()
            return [self._record(row) for row in rows], total
        rows = self.db.fetchall(
            f"{_LOAN_SELECT} {clause} ORDER BY l.due_at, l.id",
            parameters,
        )
        records = [self._record(row) for row in rows]
        if q.strip():
            folded = q.strip().translate({ord("İ"): "i", ord("I"): "ı"}).casefold()
            records = [
                record
                for record in records
                if folded
                in (
                    f"{record.title_snapshot} {record.member_name} "
                    f"{record.member_number or ''} {record.inventory_code_snapshot or ''}"
                )
                .translate({ord("İ"): "i", ord("I"): "ı"})
                .casefold()
            ]
        total = len(records)
        return records[offset : offset + limit], total

    def list_overdue(self, *, now: datetime | None = None) -> list[LoanRecord]:
        items, _ = self.list_loans(status="overdue", limit=500, now=now)
        return items

    def member_history(
        self, member_id: int, *, limit: int = 100, offset: int = 0
    ) -> tuple[list[LoanRecord], int]:
        total_row = self.db.fetchone(
            "SELECT COUNT(*) FROM loan WHERE member_id = ?", (member_id,)
        )
        rows = self.db.fetchall(
            f"{_LOAN_SELECT} WHERE l.member_id = ? ORDER BY l.loaned_at DESC LIMIT ? OFFSET ?",
            (member_id, max(1, min(int(limit), 500)), max(0, int(offset))),
        )
        return [self._record(row) for row in rows], int(total_row[0]) if total_row else 0

    def active_counts(self, edition_ids: Iterable[int]) -> dict[int, int]:
        """Baskı başına açık ödünç sayısı (liste/OPAC müsaitlik gösterimi)."""

        ids = [int(value) for value in edition_ids]
        if not ids:
            return {}
        marks = ",".join("?" for _ in ids)
        rows = self.db.fetchall(
            f"""
            SELECT edition_id, COUNT(*) AS count FROM loan
            WHERE returned_at IS NULL AND edition_id IN ({marks})
            GROUP BY edition_id
            """,
            ids,
        )
        return {int(row["edition_id"]): int(row["count"]) for row in rows}

    def hold_counts(self, edition_ids: Iterable[int]) -> dict[int, int]:
        """Baskı başına bekleyen (active+ready) rezervasyon sayısı (OPAC için)."""

        ids = [int(value) for value in edition_ids]
        if not ids:
            return {}
        marks = ",".join("?" for _ in ids)
        rows = self.db.fetchall(
            f"""
            SELECT edition_id, COUNT(*) AS count FROM hold
            WHERE status IN ('active', 'ready') AND edition_id IN ({marks})
            GROUP BY edition_id
            """,
            ids,
        )
        return {int(row["edition_id"]): int(row["count"]) for row in rows}

    def stats(self, *, now: datetime | None = None) -> dict[str, int]:
        now_dt = _now_dt(now)
        today = now_dt.date().isoformat()
        month_prefix = today[:7]
        row = self.db.fetchone(
            """
            SELECT
                (SELECT COUNT(*) FROM loan WHERE returned_at IS NULL) AS active,
                (SELECT COUNT(*) FROM loan
                 WHERE returned_at IS NULL AND due_at < ?) AS overdue,
                (SELECT COUNT(*) FROM loan WHERE substr(loaned_at, 1, 7) = ?) AS this_month,
                (SELECT COUNT(*) FROM loan WHERE substr(loaned_at, 1, 10) = ?) AS today_out,
                (SELECT COUNT(*) FROM loan
                 WHERE substr(returned_at, 1, 10) = ?) AS today_in
            """,
            (today, month_prefix, today, today),
        )
        assert row is not None
        return {
            key: int(row[key])
            for key in ("active", "overdue", "this_month", "today_out", "today_in")
        }

    @staticmethod
    def _record(row: Mapping[str, Any]) -> LoanRecord:
        # `row` is a sqlite3.Row (live query, no hold_ready column) when read
        # straight from `loan`, or a plain dict (circulation_event replay,
        # asdict(record) round-trip) when it DOES carry hold_ready. Both raise
        # on a missing string key (IndexError/KeyError respectively).
        try:
            hold_ready = row["hold_ready"]
        except (KeyError, IndexError):
            hold_ready = None
        return LoanRecord(
            id=int(row["id"]),
            copy_id=int(row["copy_id"]) if row["copy_id"] is not None else None,
            member_id=int(row["member_id"]),
            edition_id=int(row["edition_id"]) if row["edition_id"] is not None else None,
            title_snapshot=row["title_snapshot"],
            inventory_code_snapshot=row["inventory_code_snapshot"],
            loaned_at=row["loaned_at"],
            due_at=row["due_at"],
            returned_at=row["returned_at"],
            renewal_count=int(row["renewal_count"]),
            notes=row["notes"],
            member_name=row["member_name"],
            member_class=row["member_class"],
            member_number=row["member_number"],
            member_type=row["member_type"],
            academic_period=row["academic_period"],
            snapshot_source=row["snapshot_source"],
            hold_ready=hold_ready,
        )

    # ── Rezervasyon (hold) ───────────────────────────────────────────

    _HOLD_SELECT = """
        SELECT h.*, e.title AS title, m.first_name, m.last_name, m.school_number
        FROM hold AS h
        JOIN edition AS e ON e.id = h.edition_id
        JOIN member AS m ON m.id = h.member_id
    """

    def _promote_next_hold(
        self,
        connection: sqlite3.Connection,
        *,
        edition_id: int,
        copy_id: int,
        now_dt: datetime,
        stamp: str,
    ) -> dict[str, Any] | None:
        """Bu baskı için sıradaki en eski `active` hold'u serbest kalan nüshaya
        `ready` yapar; sıra boşsa None döner. İade ve süre-dolumu ilerletmesinin
        her ikisi de bunu çağırır."""

        # Devredilecek nüsha hâlâ yaşıyor ve rafta olmalı: düşülmüş ya da bu
        # arada ödünç verilmiş bir nüshaya devir, kuyruktaki her üyeye sırayla
        # asılsız "kitap ayrıldı" bildirimi gönderip kuyruğu sessizce eritir.
        copy_alive = connection.execute(
            """
            SELECT 1 FROM copy AS c
            WHERE c.id = ? AND c.status = 'active'
              AND NOT EXISTS (
                  SELECT 1 FROM loan WHERE copy_id = c.id AND returned_at IS NULL
              )
            """,
            (copy_id,),
        ).fetchone()
        if copy_alive is None:
            return None
        next_row = connection.execute(
            "SELECT * FROM hold WHERE edition_id = ? AND status = 'active' "
            "ORDER BY created_at, id LIMIT 1",
            (edition_id,),
        ).fetchone()
        if next_row is None:
            return None
        expires = (now_dt.date() + timedelta(days=self.settings.hold_pickup_days)).isoformat()
        connection.execute(
            "UPDATE hold SET status = 'ready', ready_at = ?, ready_copy_id = ?, "
            "expires_at = ? WHERE id = ?",
            (stamp, copy_id, expires, next_row["id"]),
        )
        member = connection.execute(
            "SELECT first_name, last_name FROM member WHERE id = ?", (next_row["member_id"],)
        ).fetchone()
        edition = connection.execute(
            "SELECT title FROM edition WHERE id = ?", (edition_id,)
        ).fetchone()
        title = edition["title"] if edition is not None else "bilinmiyor"
        member_name = (
            f"{member['first_name']} {member['last_name']}".strip()
            if member is not None
            else "Bilinmeyen üye"
        )
        Notifications.enqueue(
            connection,
            kind="hold_ready",
            member_id=int(next_row["member_id"]),
            ref_kind="hold",
            ref_id=int(next_row["id"]),
            title="Rezervasyon hazır",
            body=f'"{title}" adlı kitap {member_name} için ayrıldı; son alma tarihi {expires}.',
            # Son alma tarihi anahtara girer: aynı hold ikinci kez hazırlanırsa
            # (örn. ilk ayrılan nüsha düşüldü, sonra başka nüsha boşaldı) yeni
            # bildirim dedupe'a takılmasın.
            dedupe_key=f"hold_ready:{int(next_row['id'])}:{expires}",
            now=now_dt,
        )
        return {
            "hold_id": int(next_row["id"]),
            "member_id": int(next_row["member_id"]),
            "member_name": member_name,
            "title": title,
            "expires_at": expires,
        }

    def promote_next_hold_in_connection(
        self,
        connection: sqlite3.Connection,
        *,
        edition_id: int,
        copy_id: int,
        now: datetime | None = None,
    ) -> dict[str, Any] | None:
        """Dış modüllerin (örn. düşüm) AYNI transaction içinde devir zincirini
        çalıştırabilmesi için ince kamu sarmalayıcı."""

        now_dt = _now_dt(now)
        return self._promote_next_hold(
            connection,
            edition_id=edition_id,
            copy_id=copy_id,
            now_dt=now_dt,
            stamp=_stamp(now_dt),
        )

    def create_hold(
        self,
        *,
        edition_id: int,
        member_id: int,
        request_id: str | None = None,
        now: datetime | None = None,
    ) -> HoldRecord:
        now_dt = _now_dt(now)
        stamp = _stamp(now_dt)
        request_id = self._request_id(request_id)
        with self.db.transaction(immediate=True) as connection:
            existing = connection.execute(
                self._HOLD_SELECT + " WHERE h.request_id = ?", (request_id,)
            ).fetchone()
            if existing is not None:
                if int(existing["edition_id"]) != edition_id or int(existing["member_id"]) != member_id:
                    raise StateConflictError(
                        "Bu request_id daha önce farklı bir rezervasyon için kullanılmış"
                    )
                return self._hold_record(existing)
            member = connection.execute(
                "SELECT is_active FROM member WHERE id = ?", (member_id,)
            ).fetchone()
            if member is None:
                raise KeyError("Üye bulunamadı")
            if not member["is_active"]:
                raise StateConflictError("Üye pasif durumda; rezervasyon yapılamaz")
            edition = connection.execute(
                "SELECT id FROM edition WHERE id = ?", (edition_id,)
            ).fetchone()
            if edition is None:
                raise KeyError("Kitap bulunamadı")
            available = connection.execute(
                """
                SELECT 1 FROM copy AS c
                WHERE c.edition_id = ? AND c.status = 'active'
                  AND NOT EXISTS(SELECT 1 FROM loan WHERE copy_id = c.id AND returned_at IS NULL)
                  AND c.id NOT IN (
                      SELECT ready_copy_id FROM hold
                      WHERE status = 'ready' AND ready_copy_id IS NOT NULL
                  )
                LIMIT 1
                """,
                (edition_id,),
            ).fetchone()
            if available is not None:
                raise StateConflictError("Rafta uygun nüsha var; rezervasyon gerekmez")
            duplicate = connection.execute(
                "SELECT 1 FROM hold WHERE edition_id = ? AND member_id = ? "
                "AND status IN ('active', 'ready')",
                (edition_id, member_id),
            ).fetchone()
            if duplicate is not None:
                raise StateConflictError("Bu üyenin bu kitap için zaten bir rezervasyonu var")
            limit = self.settings.hold_max_per_member
            count = connection.execute(
                "SELECT COUNT(*) FROM hold WHERE member_id = ? AND status IN ('active', 'ready')",
                (member_id,),
            ).fetchone()[0]
            if int(count) >= limit:
                raise StateConflictError(f"Üye en fazla {limit} rezervasyon yapabilir")
            cursor = connection.execute(
                "INSERT INTO hold(edition_id, member_id, status, created_at, request_id) "
                "VALUES (?, ?, 'active', ?, ?)",
                (edition_id, member_id, stamp, request_id),
            )
            hold_id = int(cursor.lastrowid)
            row = connection.execute(self._HOLD_SELECT + " WHERE h.id = ?", (hold_id,)).fetchone()
            assert row is not None
            return self._hold_record(row)

    def cancel_hold(self, hold_id: int, *, now: datetime | None = None) -> HoldRecord:
        now_dt = _now_dt(now)
        with self.db.transaction(immediate=True) as connection:
            row = connection.execute("SELECT * FROM hold WHERE id = ?", (hold_id,)).fetchone()
            if row is None:
                raise KeyError("Rezervasyon bulunamadı")
            if row["status"] == "cancelled":
                return self._hold_record(
                    connection.execute(
                        self._HOLD_SELECT + " WHERE h.id = ?", (hold_id,)
                    ).fetchone()
                )
            if row["status"] not in ("active", "ready"):
                raise StateConflictError("Bu rezervasyon iptal edilemez durumda")
            connection.execute("UPDATE hold SET status = 'cancelled' WHERE id = ?", (hold_id,))
            if row["status"] == "ready" and row["ready_copy_id"] is not None:
                self._promote_next_hold(
                    connection,
                    edition_id=int(row["edition_id"]),
                    copy_id=int(row["ready_copy_id"]),
                    now_dt=now_dt,
                    stamp=_stamp(now_dt),
                )
            updated = connection.execute(
                self._HOLD_SELECT + " WHERE h.id = ?", (hold_id,)
            ).fetchone()
            assert updated is not None
            return self._hold_record(updated)

    def get_hold(self, hold_id: int) -> HoldRecord | None:
        row = self.db.fetchone(self._HOLD_SELECT + " WHERE h.id = ?", (hold_id,))
        return self._hold_record(row) if row is not None else None

    def advance_expired_holds(self, *, now: datetime | None = None) -> int:
        """Süresi geçen `ready` hold'ları `expired` yapar, sıradakini `ready`ye
        taşır. Hold okuma/listelemede tembel çağrılır; günlük bakım da çağırır."""

        now_dt = _now_dt(now)
        today = now_dt.date().isoformat()
        # Tembel yol her hold listelemesinde çağrılır; süresi dolan yokken
        # yazma kilidi (BEGIN IMMEDIATE) almak banko akışıyla boş yere çekişir.
        pending = self.db.fetchone(
            "SELECT 1 FROM hold WHERE status = 'ready' AND expires_at IS NOT NULL "
            "AND expires_at < ? LIMIT 1",
            (today,),
        )
        if pending is None:
            return 0
        advanced = 0
        with self.db.transaction(immediate=True) as connection:
            expired_rows = connection.execute(
                "SELECT * FROM hold WHERE status = 'ready' AND expires_at IS NOT NULL "
                "AND expires_at < ?",
                (today,),
            ).fetchall()
            for row in expired_rows:
                connection.execute("UPDATE hold SET status = 'expired' WHERE id = ?", (row["id"],))
                if row["ready_copy_id"] is not None:
                    self._promote_next_hold(
                        connection,
                        edition_id=int(row["edition_id"]),
                        copy_id=int(row["ready_copy_id"]),
                        now_dt=now_dt,
                        stamp=_stamp(now_dt),
                    )
                advanced += 1
        return advanced

    def list_holds(
        self,
        *,
        member_id: int | None = None,
        edition_id: int | None = None,
        status: str | None = None,
        limit: int = 100,
        offset: int = 0,
        now: datetime | None = None,
    ) -> list[HoldRecord]:
        self.advance_expired_holds(now=now)
        where: list[str] = []
        parameters: list[Any] = []
        if member_id is not None:
            where.append("h.member_id = ?")
            parameters.append(member_id)
        if edition_id is not None:
            where.append("h.edition_id = ?")
            parameters.append(edition_id)
        if status is not None:
            where.append("h.status = ?")
            parameters.append(status)
        clause = f"WHERE {' AND '.join(where)}" if where else ""
        limit = max(1, min(int(limit), 500))
        offset = max(0, int(offset))
        rows = self.db.fetchall(
            f"{self._HOLD_SELECT} {clause} ORDER BY h.created_at, h.id LIMIT ? OFFSET ?",
            (*parameters, limit, offset),
        )
        return [self._hold_record(row) for row in rows]

    @staticmethod
    def _hold_record(row: sqlite3.Row) -> HoldRecord:
        keys = row.keys()
        return HoldRecord(
            id=int(row["id"]),
            edition_id=int(row["edition_id"]),
            member_id=int(row["member_id"]),
            status=row["status"],
            created_at=row["created_at"],
            ready_at=row["ready_at"],
            ready_copy_id=int(row["ready_copy_id"]) if row["ready_copy_id"] is not None else None,
            expires_at=row["expires_at"],
            title=row["title"] if "title" in keys else "",
            member_name=(
                f"{row['first_name']} {row['last_name']}".strip() if "first_name" in keys else ""
            ),
            school_number=row["school_number"] if "school_number" in keys else None,
        )

    # ── Üye yasağı / af ──────────────────────────────────────────────

    def add_block(
        self,
        member_id: int,
        *,
        reason: str,
        end_date: str | None = None,
        now: datetime | None = None,
    ) -> MemberBlockRecord:
        reason = (reason or "").strip()
        if not reason:
            raise ValueError("Yasak gerekçesi zorunludur")
        now_dt = _now_dt(now)
        stamp = _stamp(now_dt)
        today = now_dt.date().isoformat()
        with self.db.transaction(immediate=True) as connection:
            member = connection.execute(
                "SELECT id FROM member WHERE id = ?", (member_id,)
            ).fetchone()
            if member is None:
                raise KeyError("Üye bulunamadı")
            cursor = connection.execute(
                "INSERT INTO member_block(member_id, kind, start_date, end_date, reason, "
                "created_at) VALUES (?, 'manual', ?, ?, ?, ?)",
                (member_id, today, end_date, reason, stamp),
            )
            block_id = int(cursor.lastrowid)
            row = connection.execute(
                "SELECT * FROM member_block WHERE id = ?", (block_id,)
            ).fetchone()
            assert row is not None
            return self._block_record(row)

    def lift_block(
        self,
        member_id: int,
        block_id: int,
        *,
        reason: str | None = None,
        now: datetime | None = None,
    ) -> MemberBlockRecord:
        stamp = _stamp(_now_dt(now))
        with self.db.transaction(immediate=True) as connection:
            row = connection.execute(
                "SELECT * FROM member_block WHERE id = ? AND member_id = ?",
                (block_id, member_id),
            ).fetchone()
            if row is None:
                raise KeyError("Yasak kaydı bulunamadı")
            if row["lifted_at"] is not None:
                raise StateConflictError("Bu yasak zaten kaldırılmış")
            connection.execute(
                "UPDATE member_block SET lifted_at = ?, lift_reason = ? WHERE id = ?",
                (stamp, (reason or "").strip() or None, block_id),
            )
            updated = connection.execute(
                "SELECT * FROM member_block WHERE id = ?", (block_id,)
            ).fetchone()
            assert updated is not None
            return self._block_record(updated)

    def grant_amnesty(
        self, member_id: int, *, reason: str, now: datetime | None = None
    ) -> MemberBlockRecord:
        reason = (reason or "").strip()
        if not reason:
            raise ValueError("Af gerekçesi zorunludur")
        now_dt = _now_dt(now)
        today = now_dt.date()
        stamp = _stamp(now_dt)
        with self.db.transaction(immediate=True) as connection:
            member = connection.execute(
                "SELECT id FROM member WHERE id = ?", (member_id,)
            ).fetchone()
            if member is None:
                raise KeyError("Üye bulunamadı")
            # Ceza hesabı ve af kaydı AYNI yazma kilidi altında: hesap tx
            # dışında yapılsaydı iki eşzamanlı af, aradaki bir iadeyi ikinci
            # afla söndürebilirdi (TOCTOU).
            penalty_end = self._penalty_end_in_connection(connection, member_id, today)
            if penalty_end is None:
                raise StateConflictError("Bu üyenin süren bir cezası yok")
            cursor = connection.execute(
                "INSERT INTO member_block(member_id, kind, start_date, end_date, reason, "
                "created_at) VALUES (?, 'auto_overdue_waiver', ?, ?, ?, ?)",
                (member_id, now_dt.date().isoformat(), penalty_end.isoformat(), reason, stamp),
            )
            block_id = int(cursor.lastrowid)
            row = connection.execute(
                "SELECT * FROM member_block WHERE id = ?", (block_id,)
            ).fetchone()
            assert row is not None
            return self._block_record(row)

    def list_blocks(self, member_id: int) -> list[MemberBlockRecord]:
        rows = self.db.fetchall(
            "SELECT * FROM member_block WHERE member_id = ? ORDER BY created_at DESC, id DESC",
            (member_id,),
        )
        return [self._block_record(row) for row in rows]

    def active_manual_block(
        self, member_id: int, *, now: datetime | None = None
    ) -> MemberBlockRecord | None:
        today = _now_dt(now).date().isoformat()
        row = self.db.fetchone(self._MANUAL_BLOCK_SQL, (member_id, today, today))
        return self._block_record(row) if row is not None else None

    @staticmethod
    def _block_record(row: sqlite3.Row) -> MemberBlockRecord:
        return MemberBlockRecord(
            id=int(row["id"]),
            member_id=int(row["member_id"]),
            kind=row["kind"],
            start_date=row["start_date"],
            end_date=row["end_date"],
            reason=row["reason"],
            created_at=row["created_at"],
            lifted_at=row["lifted_at"],
            lift_reason=row["lift_reason"],
        )
