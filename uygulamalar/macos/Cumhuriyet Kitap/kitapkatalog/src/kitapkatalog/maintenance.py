"""Günlük bakım: süresi dolan rezervasyonları ilerlet, gecikme bildirimi üret.

``AutoBackup.run_if_due`` deseniyle birebir: son koşum damgası ``app_setting``
tablosunda tutulur, günde bir çalışır. ``webapp/server.py`` bunu da bir arka
plan thread'inde, yedek zamanlayıcısının yanında başlatır.
"""

from __future__ import annotations

from datetime import UTC, datetime

from kitapkatalog.database import Database
from kitapkatalog.loans import Loans
from kitapkatalog.notifications import Notifications
from kitapkatalog.settings import AppSettings


class DailyMaintenance:
    def __init__(self, database: Database, settings: AppSettings) -> None:
        self.db = database
        self.settings = settings
        self.loans = Loans(database, settings)
        self.notifications = Notifications(database)

    def run_if_due(self, *, now: datetime | None = None) -> dict[str, int] | None:
        """Bugün henüz çalışmadıysa çalışır; çalışmışsa None döner."""

        # Yerel saat: ödünç/ceza hesapları yerel tarihle çalışır; bakım UTC
        # tarihiyle koşarsa TRT 00:00-03:00 arasında "dün" süresi dolanlar o
        # tura girmezdi (astimezone() sistem dilimine çevirir).
        now = now or datetime.now(UTC).astimezone()
        last = self.settings.last_maintenance_at
        if last and last[:10] == now.date().isoformat():
            return None
        return self.run(now=now)

    def run(self, *, now: datetime | None = None) -> dict[str, int]:
        now = now or datetime.now(UTC).astimezone()
        advanced = self.loans.advance_expired_holds(now=now)
        notified = self._notify_overdue(now=now)
        self.settings.set("last_maintenance_at", now.isoformat(timespec="seconds"))
        return {"holds_advanced": advanced, "overdue_notified": notified}

    def _notify_overdue(self, *, now: datetime) -> int:
        """Geciken her üye için günde tek, dedupe_key ile idempotent bildirim."""

        today = now.date().isoformat()
        overdue = self.loans.list_overdue(now=now)
        by_member: dict[int, list] = {}
        for record in overdue:
            by_member.setdefault(record.member_id, []).append(record)
        if not by_member:
            return 0
        count = 0
        with self.db.transaction(immediate=True) as connection:
            for member_id, records in by_member.items():
                titles = ", ".join(record.title_snapshot for record in records[:3])
                extra = f" (+{len(records) - 3} kitap daha)" if len(records) > 3 else ""
                Notifications.enqueue(
                    connection,
                    kind="overdue",
                    member_id=member_id,
                    ref_kind="member",
                    ref_id=member_id,
                    title="Gecikmiş kitap",
                    body=f"{len(records)} kitap gecikmiş: {titles}{extra}",
                    dedupe_key=f"overdue:{member_id}:{today}",
                    now=now,
                )
                count += 1
        return count
