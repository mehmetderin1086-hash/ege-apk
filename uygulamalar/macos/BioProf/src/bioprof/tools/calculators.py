from __future__ import annotations

import math
import re
import statistics
from collections.abc import Callable, Mapping
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator, model_validator


class ToolError(ValueError):
    """A safe, user-facing validation error raised by a scientific tool."""


class ToolResult(BaseModel):
    tool: str
    result: dict[str, Any]
    formula: str
    inputs: dict[str, Any]
    warnings: list[str] = Field(default_factory=list)
    educational_only: bool = True


class _StrictInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    @field_validator("*", mode="before")
    @classmethod
    def reject_bool_numbers(cls, value: Any) -> Any:
        if isinstance(value, bool):
            raise ValueError("Boolean values are not valid scientific measurements")
        return value


def _positive(value: float, name: str, *, allow_zero: bool = False) -> float:
    if not math.isfinite(value):
        raise ToolError(f"{name} sonlu bir sayı olmalıdır")
    if value < 0 or (value == 0 and not allow_zero):
        qualifier = "negatif olamaz" if allow_zero else "sıfırdan büyük olmalıdır"
        raise ToolError(f"{name} {qualifier}")
    return value


class DilutionInput(_StrictInput):
    stock_concentration: float
    target_concentration: float
    final_volume: float
    concentration_unit: str = "mM"
    volume_unit: str = "mL"


class MolarityInput(_StrictInput):
    volume_liters: float
    moles: float | None = None
    mass_grams: float | None = None
    molar_mass_g_mol: float | None = None

    @model_validator(mode="after")
    def exactly_one_amount(self) -> MolarityInput:
        direct = self.moles is not None
        mass_based = self.mass_grams is not None or self.molar_mass_g_mol is not None
        if direct == mass_based:
            raise ValueError("Moles or the mass+molar-mass pair must be supplied")
        if mass_based and (self.mass_grams is None or self.molar_mass_g_mol is None):
            raise ValueError("mass_grams and molar_mass_g_mol must be supplied together")
        return self


class HardyWeinbergInput(_StrictInput):
    p: float | None = None
    q: float | None = None
    homozygous_dominant: int | None = None
    heterozygous: int | None = None
    homozygous_recessive: int | None = None

    @model_validator(mode="after")
    def select_mode(self) -> HardyWeinbergInput:
        frequency_mode = self.p is not None or self.q is not None
        counts = (
            self.homozygous_dominant,
            self.heterozygous,
            self.homozygous_recessive,
        )
        count_mode = any(value is not None for value in counts)
        if frequency_mode == count_mode:
            raise ValueError("Supply p/q or all three genotype counts")
        if count_mode and any(value is None for value in counts):
            raise ValueError("All three genotype counts are required")
        return self


class EnzymeKineticsInput(_StrictInput):
    vmax: float
    substrate_concentration: float
    km: float
    hill_coefficient: float = 1.0


class SequenceInput(_StrictInput):
    sequence: str = Field(min_length=1, max_length=2_000_000)

    @field_validator("sequence")
    @classmethod
    def normalise_sequence(cls, value: str) -> str:
        return re.sub(r"\s+|\d+", "", value).upper().replace("U", "T")


class TranslateInput(SequenceInput):
    frame: int = Field(default=1, ge=1, le=3)
    stop_symbol: str = "*"


class OrfInput(SequenceInput):
    minimum_amino_acids: int = Field(default=20, ge=1, le=100_000)
    include_reverse: bool = True


class StatisticsInput(_StrictInput):
    values: list[float] = Field(min_length=1, max_length=1_000_000)


class UnitConversionInput(_StrictInput):
    value: float
    from_unit: str = Field(min_length=1, max_length=100)
    to_unit: str = Field(min_length=1, max_length=100)


DNA_RE = re.compile(r"^[ACGTRYSWKMBDHVN-]+$")
CODON_TABLE = {
    "TTT": "F",
    "TTC": "F",
    "TTA": "L",
    "TTG": "L",
    "TCT": "S",
    "TCC": "S",
    "TCA": "S",
    "TCG": "S",
    "TAT": "Y",
    "TAC": "Y",
    "TAA": "*",
    "TAG": "*",
    "TGT": "C",
    "TGC": "C",
    "TGA": "*",
    "TGG": "W",
    "CTT": "L",
    "CTC": "L",
    "CTA": "L",
    "CTG": "L",
    "CCT": "P",
    "CCC": "P",
    "CCA": "P",
    "CCG": "P",
    "CAT": "H",
    "CAC": "H",
    "CAA": "Q",
    "CAG": "Q",
    "CGT": "R",
    "CGC": "R",
    "CGA": "R",
    "CGG": "R",
    "ATT": "I",
    "ATC": "I",
    "ATA": "I",
    "ATG": "M",
    "ACT": "T",
    "ACC": "T",
    "ACA": "T",
    "ACG": "T",
    "AAT": "N",
    "AAC": "N",
    "AAA": "K",
    "AAG": "K",
    "AGT": "S",
    "AGC": "S",
    "AGA": "R",
    "AGG": "R",
    "GTT": "V",
    "GTC": "V",
    "GTA": "V",
    "GTG": "V",
    "GCT": "A",
    "GCC": "A",
    "GCA": "A",
    "GCG": "A",
    "GAT": "D",
    "GAC": "D",
    "GAA": "E",
    "GAG": "E",
    "GGT": "G",
    "GGC": "G",
    "GGA": "G",
    "GGG": "G",
}
COMPLEMENT = str.maketrans("ACGTRYSWKMBDHVN", "TGCAYRSWMKVHDBN")


def _validate_dna(sequence: str) -> str:
    sequence = sequence.replace("-", "")
    if not sequence or not DNA_RE.fullmatch(sequence):
        raise ToolError("Dizi yalnız IUPAC DNA harflerini içermelidir")
    return sequence


def dilution(data: DilutionInput) -> ToolResult:
    c1 = _positive(data.stock_concentration, "Stok konsantrasyonu")
    c2 = _positive(data.target_concentration, "Hedef konsantrasyon", allow_zero=True)
    v2 = _positive(data.final_volume, "Son hacim")
    if c2 > c1:
        raise ToolError("Seyreltmeyle hedef konsantrasyon stoktan yüksek olamaz")
    stock_volume = c2 * v2 / c1
    diluent_volume = v2 - stock_volume
    return ToolResult(
        tool="dilution",
        formula="C1 × V1 = C2 × V2",
        inputs=data.model_dump(),
        result={
            "stock_volume": stock_volume,
            "diluent_volume": diluent_volume,
            "volume_unit": data.volume_unit,
            "dilution_factor": c1 / c2 if c2 else None,
        },
    )


def molarity(data: MolarityInput) -> ToolResult:
    volume = _positive(data.volume_liters, "Hacim")
    if data.moles is not None:
        moles = _positive(data.moles, "Mol", allow_zero=True)
    else:
        assert data.mass_grams is not None
        assert data.molar_mass_g_mol is not None
        mass = _positive(float(data.mass_grams), "Kütle", allow_zero=True)
        molar_mass = _positive(float(data.molar_mass_g_mol), "Molar kütle")
        moles = mass / molar_mass
    value = moles / volume
    return ToolResult(
        tool="molarity",
        formula="M = n / V; n = m / Mr",
        inputs=data.model_dump(exclude_none=True),
        result={"molarity_mol_l": value, "moles": moles},
    )


def hardy_weinberg(data: HardyWeinbergInput) -> ToolResult:
    warnings: list[str] = []
    if data.homozygous_dominant is not None:
        assert data.heterozygous is not None
        assert data.homozygous_recessive is not None
        aa = int(data.homozygous_dominant)
        ab = int(data.heterozygous)
        bb = int(data.homozygous_recessive)
        if min(aa, ab, bb) < 0 or aa + ab + bb == 0:
            raise ToolError("Genotip sayıları negatif olamaz ve toplam sıfır olamaz")
        total = aa + ab + bb
        p = (2 * aa + ab) / (2 * total)
        observed = {"AA": aa / total, "Aa": ab / total, "aa": bb / total}
        expected_counts = {
            "AA": p * p * total,
            "Aa": 2 * p * (1 - p) * total,
            "aa": (1 - p) ** 2 * total,
        }
    else:
        if data.p is None:
            assert data.q is not None
            q = _positive(float(data.q), "q", allow_zero=True)
            p = 1 - q
        else:
            p = _positive(float(data.p), "p", allow_zero=True)
            if data.q is not None and not math.isclose(p + data.q, 1.0, abs_tol=1e-7):
                raise ToolError("p + q toplamı 1 olmalıdır")
        observed = None
        expected_counts = None
    q = 1 - p
    if not 0 <= p <= 1 or not 0 <= q <= 1:
        raise ToolError("Alel frekansları 0 ile 1 arasında olmalıdır")
    if observed is not None:
        warnings.append("Ki-kare yorumu örneklem ve varsayım kontrolü gerektirir")
    return ToolResult(
        tool="hardy_weinberg",
        formula="p + q = 1; p² + 2pq + q² = 1",
        inputs=data.model_dump(exclude_none=True),
        result={
            "p": p,
            "q": q,
            "expected_frequencies": {"AA": p * p, "Aa": 2 * p * q, "aa": q * q},
            "observed_frequencies": observed,
            "expected_counts": expected_counts,
        },
        warnings=warnings,
    )


def enzyme_kinetics(data: EnzymeKineticsInput) -> ToolResult:
    vmax = _positive(data.vmax, "Vmax")
    substrate = _positive(data.substrate_concentration, "Substrat", allow_zero=True)
    km = _positive(data.km, "Km")
    hill = _positive(data.hill_coefficient, "Hill katsayısı")
    numerator = vmax * substrate**hill
    velocity = numerator / (km**hill + substrate**hill)
    return ToolResult(
        tool="enzyme_kinetics",
        formula="v = Vmax × [S]^n / (Km^n + [S]^n)",
        inputs=data.model_dump(),
        result={"initial_velocity": velocity, "fraction_vmax": velocity / vmax},
    )


def gc_content(data: SequenceInput) -> ToolResult:
    sequence = _validate_dna(data.sequence)
    resolved = [base for base in sequence if base in "ACGT"]
    gc = sum(base in "GC" for base in resolved)
    warnings = []
    if len(resolved) != len(sequence):
        warnings.append("Belirsiz IUPAC bazları GC yüzdesinin paydasına katılmadı")
    value = 100 * gc / len(resolved) if resolved else 0.0
    return ToolResult(
        tool="gc_content",
        formula="GC% = 100 × (G + C) / (A + C + G + T)",
        inputs={"sequence_length": len(sequence)},
        result={"gc_percent": value, "resolved_bases": len(resolved), "gc_bases": gc},
        warnings=warnings,
    )


def _translate(sequence: str, frame: int = 1, stop_symbol: str = "*") -> str:
    sequence = sequence[frame - 1 :]
    amino_acids: list[str] = []
    for position in range(0, len(sequence) - 2, 3):
        amino = CODON_TABLE.get(sequence[position : position + 3], "X")
        amino_acids.append(stop_symbol if amino == "*" else amino)
    return "".join(amino_acids)


def translate(data: TranslateInput) -> ToolResult:
    sequence = _validate_dna(data.sequence)
    protein = _translate(sequence, data.frame, data.stop_symbol)
    return ToolResult(
        tool="translate",
        formula="Standart genetik kod; seçilen okuma çerçevesinde üçlü kodonlar",
        inputs={"sequence_length": len(sequence), "frame": data.frame},
        result={"protein": protein, "amino_acids": len(protein)},
        warnings=["Bu sonuç standart nükleer kodu kullanır; organel kodları farklı olabilir"],
    )


def _find_orfs_on_strand(sequence: str, strand: int, minimum: int) -> list[dict[str, Any]]:
    found: list[dict[str, Any]] = []
    for frame in range(3):
        start: int | None = None
        for position in range(frame, len(sequence) - 2, 3):
            codon = sequence[position : position + 3]
            if start is None and codon == "ATG":
                start = position
            elif start is not None and codon in {"TAA", "TAG", "TGA"}:
                amino_length = (position - start) // 3
                if amino_length >= minimum:
                    found.append(
                        {
                            "strand": strand,
                            "frame": frame + 1,
                            "start": start + 1,
                            "end": position + 3,
                            "nucleotides": position + 3 - start,
                            "protein": _translate(sequence[start : position + 3]),
                        }
                    )
                start = None
    return found


def find_orfs(data: OrfInput) -> ToolResult:
    sequence = _validate_dna(data.sequence)
    found = _find_orfs_on_strand(sequence, 1, data.minimum_amino_acids)
    if data.include_reverse:
        reverse = sequence.translate(COMPLEMENT)[::-1]
        reverse_orfs = _find_orfs_on_strand(reverse, -1, data.minimum_amino_acids)
        for item in reverse_orfs:
            start, end = int(item["start"]), int(item["end"])
            item["start"] = len(sequence) - end + 1
            item["end"] = len(sequence) - start + 1
        found.extend(reverse_orfs)
    found.sort(key=lambda item: (-int(item["nucleotides"]), int(item["start"])))
    return ToolResult(
        tool="find_orfs",
        formula="ATG ile başlayan ve in-frame TAA/TAG/TGA ile biten açık okuma çerçeveleri",
        inputs={"sequence_length": len(sequence), **data.model_dump(exclude={"sequence"})},
        result={"orfs": found, "count": len(found)},
        warnings=["Alternatif başlangıç kodonları ve dairesel genom geçişleri taranmaz"],
    )


def descriptive_statistics(data: StatisticsInput) -> ToolResult:
    values = [float(value) for value in data.values]
    if not all(math.isfinite(value) for value in values):
        raise ToolError("Tüm değerler sonlu olmalıdır")
    count = len(values)
    sample_sd = statistics.stdev(values) if count > 1 else None
    result = {
        "count": count,
        "mean": statistics.fmean(values),
        "median": statistics.median(values),
        "minimum": min(values),
        "maximum": max(values),
        "sample_standard_deviation": sample_sd,
        "standard_error": sample_sd / math.sqrt(count) if sample_sd is not None else None,
    }
    return ToolResult(
        tool="statistics",
        formula="x̄ = Σx/n; s = √(Σ(x-x̄)²/(n-1)); SEM = s/√n",
        inputs={"values": values},
        result=result,
        warnings=["Tek değer için örnek standart sapması tanımsızdır"] if count == 1 else [],
    )


def convert_units(data: UnitConversionInput) -> ToolResult:
    _positive(abs(data.value), "Değerin mutlak değeri", allow_zero=True)
    try:
        import pint
    except ImportError as exc:  # pragma: no cover - dependency is in the base install
        raise ToolError("Birim dönüşümü için 'pint' paketi kurulmalıdır") from exc
    registry: Any = pint.UnitRegistry(autoconvert_offset_to_baseunit=True)
    try:
        converted = (data.value * registry(data.from_unit)).to(data.to_unit)
    except Exception as exc:
        raise ToolError(f"Uyumsuz veya bilinmeyen birim: {exc}") from exc
    return ToolResult(
        tool="convert_units",
        formula=f"{data.value} {data.from_unit} → {data.to_unit}",
        inputs=data.model_dump(),
        result={"value": float(converted.magnitude), "unit": f"{converted.units:~}"},
    )


ToolFunction = Callable[[Any], ToolResult]


class ScientificToolRegistry:
    """Explicit allow-list used by APIs and agents.

    There is intentionally no arbitrary expression evaluator and no medical
    dosing operation.  Attempts to invoke a non-listed tool fail closed.
    """

    _tools: Mapping[str, tuple[type[BaseModel], ToolFunction]] = {
        "dilution": (DilutionInput, dilution),
        "molarity": (MolarityInput, molarity),
        "hardy_weinberg": (HardyWeinbergInput, hardy_weinberg),
        "enzyme_kinetics": (EnzymeKineticsInput, enzyme_kinetics),
        "gc_content": (SequenceInput, gc_content),
        "translate": (TranslateInput, translate),
        "find_orfs": (OrfInput, find_orfs),
        "statistics": (StatisticsInput, descriptive_statistics),
        "convert_units": (UnitConversionInput, convert_units),
    }

    @classmethod
    def names(cls) -> list[str]:
        return sorted(cls._tools)

    @classmethod
    def schemas(cls) -> dict[str, dict[str, Any]]:
        return {name: model.model_json_schema() for name, (model, _) in cls._tools.items()}

    @classmethod
    def run(cls, name: str, arguments: Mapping[str, Any]) -> ToolResult:
        if name not in cls._tools:
            raise ToolError(f"Araç izinli değil: {name}")
        model, function = cls._tools[name]
        try:
            payload = model.model_validate(dict(arguments))
        except ValidationError as exc:
            raise ToolError(str(exc)) from exc
        return function(payload)
