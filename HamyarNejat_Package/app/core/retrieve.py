"""
بازیابی اطلاعات از پایگاه دانش محلی و تولید پاسخ
Retrieval from the local knowledge base and response generation.
"""

import os
import logging

import lancedb
from langchain_community.embeddings import OllamaEmbeddings
from langchain_community.llms import Ollama

from core.config import (
    OLLAMA_BASE_URL,
    EMBED_MODEL,
    LLM_MODEL,
    KEEP_ALIVE,
    REQUEST_TIMEOUT,
    NUM_CTX,
    TOP_K,
    TABLE_NAME,
    CATEGORY_MAPPING,
)

logger = logging.getLogger(__name__)

DB_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "lancedb_data")


class RetrievalError(Exception):
    """پایگاه دانش در دسترس نیست یا جستجو با خطا مواجه شد."""


class GenerationError(Exception):
    """ارتباط با موتور هوش مصنوعی محلی برقرار نشد."""


# -----------------------------------------------------------------------------
# Clients
#
# These are module-level singletons. Building a new client per call was cheap
# but meant base_url, timeout and keep_alive had to be repeated in three places
# and were in fact omitted everywhere, so every call used langchain's default
# of http://localhost:11434 with a short timeout.
# -----------------------------------------------------------------------------
_embedder = None
_llm = None


def get_embedder() -> OllamaEmbeddings:
    global _embedder
    if _embedder is None:
        _embedder = OllamaEmbeddings(
            model=EMBED_MODEL,
            base_url=OLLAMA_BASE_URL,
        )
    return _embedder


def get_llm() -> Ollama:
    global _llm
    if _llm is None:
        _llm = Ollama(
            model=LLM_MODEL,
            base_url=OLLAMA_BASE_URL,
            keep_alive=KEEP_ALIVE,
            timeout=REQUEST_TIMEOUT,
            num_ctx=NUM_CTX,
            temperature=0.2,  # low: emergency guidance should not be creative
        )
    return _llm


# -----------------------------------------------------------------------------
# Retrieval
# -----------------------------------------------------------------------------
def retrieve_context(query: str, category: str, top_k: int = None) -> str:
    """
    واکشی اطلاعات با استفاده از فیلتر متادیتا (Pre-filtering).

    CHANGED: this function no longer swallows exceptions and returns "".
    Silently returning empty context caused the assistant to answer emergency
    questions with no grounding while appearing to work normally. Failures now
    raise RetrievalError so the UI can tell the user the knowledge base is
    unavailable.
    """
    if top_k is None:
        top_k = TOP_K

    category_en = CATEGORY_MAPPING.get(category)
    if not category_en:
        raise RetrievalError(f"دسته‌بندی نامعتبر است: {category}")

    if not os.path.isdir(DB_PATH):
        raise RetrievalError(
            "پایگاه دانش یافت نشد. لطفاً ابتدا فرآیند ingest اجرا شود."
        )

    try:
        db = lancedb.connect(DB_PATH)
    except Exception as exc:
        logger.exception("LanceDB connection failed")
        raise RetrievalError("اتصال به پایگاه دانش برقرار نشد.") from exc

    if TABLE_NAME not in db.table_names():
        raise RetrievalError(
            "جدول پایگاه دانش وجود ندارد. لطفاً ابتدا فرآیند ingest اجرا شود."
        )

    table = db.open_table(TABLE_NAME)

    try:
        query_vector = get_embedder().embed_query(query)
    except Exception as exc:
        logger.exception("Embedding failed")
        raise RetrievalError(
            f"تبدیل سوال به بردار ممکن نشد. مدل «{EMBED_MODEL}» در دسترس نیست."
        ) from exc

    try:
        results = (
            table.search(query_vector)
            .where(f"category = '{category_en}'")
            .limit(top_k)
            .to_list()
        )
    except Exception as exc:
        # The most likely cause is a dimension mismatch: the table was built
        # with a different embedding model than the one querying it.
        logger.exception("Vector search failed")
        raise RetrievalError(
            "جستجو در پایگاه دانش با خطا مواجه شد. "
            "احتمالاً مدل بردارساز با مدل زمان ساخت پایگاه داده متفاوت است."
        ) from exc

    if not results:
        return ""

    return "\n\n---\n\n".join(res["text"] for res in results)


# -----------------------------------------------------------------------------
# Prompting
# -----------------------------------------------------------------------------
_SYSTEM_PREAMBLE = """شما یک دستیار هوش مصنوعی مستقل برای مدیریت بحران و شرایط اضطراری هستید (همیار نجات آفلاین).
لطفاً تنها با استفاده از اطلاعات مرجع زیر به سوال کاربر پاسخ دقیق و کاربردی بدهید.
اگر پاسخ در اطلاعات مرجع وجود نداشت، راهنمایی‌های کلی و ایمن ارائه دهید اما حتماً ذکر کنید که این بخش از اطلاعات در پایگاه داده تخصصی شما نیست."""

_NO_CONTEXT_NOTE = "(هیچ سند مرتبطی در پایگاه دانش یافت نشد.)"


def _build_prompt(query: str, context: str, history_str: str = "") -> str:
    parts = [_SYSTEM_PREAMBLE, "", "اطلاعات مرجع:", context or _NO_CONTEXT_NOTE]
    if history_str:
        parts += ["", "تاریخچه مکالمه:", history_str]
    parts += ["", f"سوال کاربر: {query}", "پاسخ:"]
    return "\n".join(parts)


def _format_history(history_messages: list, max_turns: int = 6) -> str:
    """
    Only the most recent turns are kept. The previous version replayed the
    entire session into every prompt, so a long conversation silently
    overflowed the context window and pushed the retrieved documents out.
    """
    recent = history_messages[-max_turns:] if history_messages else []
    lines = []
    for msg in recent:
        role_fa = "کاربر" if msg.get("role") == "user" else "دستیار"
        lines.append(f"{role_fa}: {msg.get('content', '')}")
    return "\n".join(lines)


# -----------------------------------------------------------------------------
# Generation
# -----------------------------------------------------------------------------
def generate_response(query: str, context: str) -> str:
    try:
        return get_llm().invoke(_build_prompt(query, context))
    except Exception as exc:
        logger.exception("Generation failed")
        raise GenerationError(
            f"ارتباط با موتور هوش مصنوعی محلی برقرار نشد. مدل «{LLM_MODEL}» در دسترس نیست."
        ) from exc


def generate_response_with_history(query: str, context: str, history_messages: list) -> str:
    prompt = _build_prompt(query, context, _format_history(history_messages))
    try:
        return get_llm().invoke(prompt)
    except Exception as exc:
        logger.exception("Generation failed")
        raise GenerationError(
            f"ارتباط با موتور هوش مصنوعی محلی برقرار نشد. مدل «{LLM_MODEL}» در دسترس نیست."
        ) from exc


def stream_response_with_history(query: str, context: str, history_messages: list):
    """
    نسخه جریانی برای نمایش تدریجی پاسخ.
    Token-streaming variant for use with st.write_stream().

    On CPU-only hardware an 8B model can take 30-120 seconds per answer. A
    spinner for that long reads as a freeze; streaming shows progress
    immediately. Wire this into pages/1_Chat.py when you are ready.
    """
    prompt = _build_prompt(query, context, _format_history(history_messages))
    try:
        for chunk in get_llm().stream(prompt):
            yield chunk
    except Exception as exc:
        logger.exception("Streaming generation failed")
        raise GenerationError(
            f"ارتباط با موتور هوش مصنوعی محلی برقرار نشد. مدل «{LLM_MODEL}» در دسترس نیست."
        ) from exc


def check_health() -> tuple:
    """
    بررسی در دسترس بودن موتور محلی. برای نمایش وضعیت در نوار کناری.
    Returns (ok: bool, message: str).
    """
    try:
        get_embedder().embed_query("تست")
        return True, "موتور محلی در دسترس است."
    except Exception as exc:
        return False, f"موتور محلی در دسترس نیست: {exc}"
