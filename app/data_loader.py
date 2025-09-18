from __future__ import annotations

import csv
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable, List, Optional

ROOT = Path(__file__).resolve().parents[1]
LOGS_DIR = ROOT / "04-logs"


@dataclass
class EvidenceRecord:
    id: str
    file_name: str
    description: str
    source: str
    date_collected: Optional[datetime]
    relevance: str
    hash_sha256: str
    redacted_version: str
    notes: str

    @property
    def date_collected_display(self) -> str:
        return self.date_collected.strftime("%Y-%m-%d") if self.date_collected else "Unknown"


@dataclass
class TimelineEntry:
    bucket: str
    file_name: str
    recorded_at: Optional[datetime]
    source: str
    concern_flag: bool
    evidence_path: str

    @property
    def recorded_at_display(self) -> str:
        return self.recorded_at.strftime("%Y-%m-%d %H:%M") if self.recorded_at else "Unknown"


_DATE_FORMATS = [
    "%Y-%m-%d",
    "%Y-%m-%d %H:%M:%S",
    "%m/%d/%Y",
    "%Y/%m/%d",
]


def _parse_date(value: str) -> Optional[datetime]:
    if not value:
        return None
    value = value.strip().strip("\uFEFF")
    if not value or value.upper().startswith("YYYY"):
        return None
    for fmt in _DATE_FORMATS:
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            continue
    return None


def _read_csv(path: Path) -> Iterable[dict]:
    with path.open("r", encoding="utf-8-sig", newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            yield {k: (v or "").strip() for k, v in row.items()}


def load_evidence_index(path: Path = LOGS_DIR / "Evidence-Index.csv") -> List[EvidenceRecord]:
    if not path.exists():
        return []

    records: List[EvidenceRecord] = []
    for row in _read_csv(path):
        records.append(
            EvidenceRecord(
                id=row.get("ID", ""),
                file_name=row.get("FileName", ""),
                description=row.get("Description", ""),
                source=row.get("Source", ""),
                date_collected=_parse_date(row.get("DateCollected", "")),
                relevance=row.get("Relevance", ""),
                hash_sha256=row.get("HashSHA256", ""),
                redacted_version=row.get("RedactedVersion", ""),
                notes=row.get("Notes", ""),
            )
        )
    return records


def load_timeline(path: Path = LOGS_DIR / "master-chronology.csv") -> List[TimelineEntry]:
    if not path.exists():
        return []

    entries: List[TimelineEntry] = []
    for row in _read_csv(path):
        entries.append(
            TimelineEntry(
                bucket=row.get("EvidenceBucket", ""),
                file_name=row.get("FileName", ""),
                recorded_at=_parse_date(row.get("When", "")),
                source=row.get("Source", ""),
                concern_flag=row.get("ConcernFlag", "").lower() == "true",
                evidence_path=row.get("FilePath", ""),
            )
        )
    entries.sort(key=lambda entry: (entry.recorded_at or datetime.max))
    return entries


def summarize_evidence(records: Iterable[EvidenceRecord]) -> dict:
    records = list(records)
    total = len(records)
    by_source: dict[str, int] = {}
    for record in records:
        if not record.source:
            continue
        by_source[record.source] = by_source.get(record.source, 0) + 1
    return {
        "total": total,
        "by_source": dict(sorted(by_source.items(), key=lambda item: item[1], reverse=True)),
    }


def summarize_timeline(entries: Iterable[TimelineEntry]) -> dict:
    entries = list(entries)
    total = len(entries)
    flagged = sum(1 for e in entries if e.concern_flag)
    by_bucket: dict[str, int] = {}
    for entry in entries:
        if not entry.bucket:
            continue
        by_bucket[entry.bucket] = by_bucket.get(entry.bucket, 0) + 1
    return {
        "total": total,
        "flagged": flagged,
        "by_bucket": dict(sorted(by_bucket.items(), key=lambda item: item[1], reverse=True)),
    }


def load_all_data() -> dict:
    evidence = load_evidence_index()
    timeline = load_timeline()
    return {
        "evidence": evidence,
        "timeline": timeline,
        "evidence_summary": summarize_evidence(evidence),
        "timeline_summary": summarize_timeline(timeline),
    }
