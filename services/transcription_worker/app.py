import re
from datetime import datetime
from typing import List, Optional

from fastapi import FastAPI
from pydantic import BaseModel, Field

app = FastAPI(title="Mycelium Transcription Worker", version="0.1.0")

SECRET_TERMS = ("password", "token", "secret", "credential", ".env", "oauth", "certificate", "private key")
PRIVATE_TERMS = ("private", "family", "personal", "mushroom", "life", "truth", "feeling", "local")
ENTERPRISE_TERMS = ("enterprise", "deploy", "runbook", "production", "compliance", "support", "hardening")
EXAMPLE_TERMS = ("example", "demo", "sample", "template", "toy", "starter")


class MediaItem(BaseModel):
    kind: str = "file"
    original_name: str = ""
    content_type: str = ""
    bytes: int = 0
    url: str = ""


class AnalyzeRequest(BaseModel):
    title: str = ""
    text: str = ""
    capture_type: str = "note"
    person_organization: str = ""
    location: str = ""
    status: str = ""
    next_action: str = ""
    priority: str = "normal"
    media: List[MediaItem] = Field(default_factory=list)
    captured_at: Optional[str] = None


def compact(value: str) -> str:
    return " ".join(str(value or "").split()).strip()


def first_sentence(text: str) -> str:
    if not text:
      return ""
    match = re.split(r"(?<=[.!?])\s+", text.strip(), maxsplit=1)
    return match[0][:240]


def extract_emails(text: str) -> List[str]:
    return sorted(set(re.findall(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", text)))


def extract_urls(text: str) -> List[str]:
    return sorted(set(re.findall(r"https?://[^\s)>\]]+", text)))


def extract_dates(text: str) -> List[str]:
    patterns = [
        r"\b\d{4}-\d{2}-\d{2}\b",
        r"\b\d{1,2}/\d{1,2}/\d{2,4}\b",
        r"\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2}(?:,\s+\d{4})?\b",
    ]
    found = set()
    lowered = text.lower()
    for pattern in patterns:
        for match in re.findall(pattern, lowered, flags=re.IGNORECASE):
            found.add(match)
    return sorted(found)


def extract_entities(text: str, title: str, person_organization: str, location: str) -> dict:
    return {
        "emails": extract_emails(text),
        "urls": extract_urls(text),
        "dates": extract_dates(text),
        "title": compact(title),
        "person_organization": compact(person_organization),
        "location": compact(location),
    }


def classify_boundary(text: str) -> str:
    lowered = text.lower()
    if any(term in lowered for term in SECRET_TERMS):
        return "secret"
    if any(term in lowered for term in PRIVATE_TERMS):
        return "private"
    return "public"


def classify_lane(text: str, capture_type: str) -> str:
    lowered = text.lower()
    if capture_type in {"inventory", "follow-up", "opportunity", "contact"}:
        return "enterprise"
    if any(term in lowered for term in ENTERPRISE_TERMS):
        return "enterprise"
    if any(term in lowered for term in EXAMPLE_TERMS):
        return "examples"
    return "concepts"


def summarize(text: str) -> str:
    text = compact(text)
    if not text:
        return "No text provided."
    sentence = first_sentence(text)
    return sentence if sentence else text[:240]


def build_relevance(boundary: str, lane: str) -> str:
    if boundary == "secret":
        return "Hold back. This protects the root system and prevents accidental exposure."
    if boundary == "private":
        return "Keep in the truth layer. It shapes direction without becoming public payload."
    if lane == "enterprise":
        return "Promote only after the idea is repeatable, supportable, and sane under real constraints."
    if lane == "examples":
        return "Use as a safe demo with fake or sanitized data."
    return "Use as a public concept note or pattern."


@app.get("/health")
def health():
    return {"ok": True, "service": "mycelium-transcription-worker", "timestamp": datetime.utcnow().isoformat()}


@app.post("/analyze")
def analyze(payload: AnalyzeRequest):
    source_text = compact("\n".join(filter(None, [payload.title, payload.text, payload.next_action])))
    boundary = classify_boundary(source_text)
    lane = classify_lane(source_text, payload.capture_type)
    transcript = compact(payload.text) or compact(payload.title) or "No transcript text provided."
    entities = extract_entities(source_text, payload.title, payload.person_organization, payload.location)
    summary = summarize(source_text)

    return {
        "ok": True,
        "boundary": boundary,
        "lane": lane,
        "intent": payload.capture_type,
        "transcript": transcript,
        "summary": summary,
        "relevance": build_relevance(boundary, lane),
        "entities": entities,
        "recommended_record_type": payload.capture_type or "note",
        "confidence": 0.72 if transcript else 0.35,
        "captured_at": payload.captured_at or datetime.utcnow().isoformat(),
        "media_count": len(payload.media),
    }
