"""
بازیابی اطلاعات و تولید پاسخ - همیار نجات
--------------------------------------------------------------------------
مسیر: HamyarNejat_Package/app/core/retrieve.py

تغییر اصلی نسبت به نسخه قبل:
نسخه پیشین هر خطای بازیابی را با `except Exception: return ""` می‌بلعید.
نتیجه این بود که اگر Ollama خاموش بود، یا ابعاد بردارها با هم نمی‌خواند، یا
جدول پایگاه دانش وجود نداشت، مدل زبانی بدون هیچ منبعی پاسخ می‌داد و کاربر
هرگز متوجه نمی‌شد که جستجو در پایگاه دانش اصلاً انجام نشده است.

در یک سامانه امداد و نجات این رفتار خطرناک است: کاربر پاسخی می‌بیند که فکر
می‌کند از دستورالعمل‌های تأییدشده آمده، در حالی که ساخته خود مدل است.

اکنون هر خطا به صورت RetrievalError با پیام فارسی بالا می‌رود تا لایه رابط
کاربری بتواند آن را به کاربر نشان دهد.
"""

import os
import lancedb

from core.config import (
    DB_PATH,
    TABLE_NAME,
    CATEGORY_MAPPING,
    RETRIEVAL_TOP_K,
    get_embedder,
    get_llm,
)


# ===========================================================================
# استثناها
# ===========================================================================
class HamyarError(Exception):
    """
    پایه تمام خطاهای برنامه.

    message          : پیام فارسی و قابل فهم برای کاربر نهایی
    technical_detail : متن انگلیسی خطای اصلی، فقط برای لاگ و عیب‌یابی
    """

    def __init__(self, message: str, technical_detail: str = ""):
        super().__init__(message)
        self.message = message
        self.technical_detail = technical_detail


class RetrievalError(HamyarError):
    """خطا در جستجو و بازیابی اطلاعات از پایگاه دانش."""


class GenerationError(HamyarError):
    """خطا در تولید پاسخ توسط مدل زبانی."""


# ===========================================================================
# بازیابی اطلاعات
# ===========================================================================
def retrieve_context(query: str, category: str, top_k: int = None) -> str:
    """
    جستجوی برداری در پایگاه دانش با فیلتر دسته‌بندی.

    خروجی: متن مرجع یافت‌شده. اگر نتیجه‌ای نبود، رشته خالی برمی‌گرداند
            (این خطا نیست — یعنی در این دسته چیزی پیدا نشد).

    استثنا: RetrievalError در هر حالت خرابی.
    """
    if top_k is None:
        top_k = RETRIEVAL_TOP_K

    # --- ۱. اعتبارسنجی دسته‌بندی --------------------------------------
    category_en = CATEGORY_MAPPING.get(category)
    if not category_en:
        raise RetrievalError(
            "دسته‌بندی انتخاب‌شده معتبر نیست.",
            f"Unknown category label: {category!r}",
        )

    # --- ۲. وجود پایگاه داده ------------------------------------------
    if not os.path.isdir(DB_PATH):
        raise RetrievalError(
            "پایگاه دانش ساخته نشده است. لطفاً با پشتیبانی تماس بگیرید.",
            f"LanceDB directory not found: {DB_PATH}",
        )

    try:
        db = lancedb.connect(DB_PATH)
    except Exception as exc:
        raise RetrievalError(
            "اتصال به پایگاه دانش ممکن نشد.",
            f"lancedb.connect failed: {exc}",
        ) from exc

    try:
        table_names = db.table_names()
    except Exception as exc:
        raise RetrievalError(
            "خواندن پایگاه دانش ممکن نشد.",
            f"db.table_names failed: {exc}",
        ) from exc

    if TABLE_NAME not in table_names:
        raise RetrievalError(
            "پایگاه دانش خالی است و هنوز مقاله‌ای پردازش نشده است.",
            f"Table {TABLE_NAME!r} missing. Available: {table_names}",
        )

    try:
        table = db.open_table(TABLE_NAME)
    except Exception as exc:
        raise RetrievalError(
            "باز کردن پایگاه دانش ممکن نشد.",
            f"open_table failed: {exc}",
        ) from exc

    # --- ۳. تبدیل پرسش به بردار ---------------------------------------
    # اگر موتور محلی خاموش باشد یا مدل bge-m3 موجود نباشد، خطا اینجا رخ می‌دهد.
    try:
        embedder = get_embedder()
        query_vector = embedder.embed_query(query)
    except Exception as exc:
        raise RetrievalError(
            "موتور محلی هوش مصنوعی پاسخ نمی‌دهد. "
            "لطفاً برنامه را ببندید و دوباره اجرا کنید.",
            f"embed_query failed: {exc}",
        ) from exc

    if not query_vector:
        raise RetrievalError(
            "تبدیل سوال به بردار جستجو ناموفق بود.",
            "embed_query returned an empty vector",
        )

    # --- ۴. جستجوی برداری ---------------------------------------------
    # ناسازگاری ابعاد بردار (مثلاً اگر ingest با مدل دیگری اجرا شده باشد)
    # دقیقاً همین‌جا خودش را نشان می‌دهد.
    try:
        results = (
            table.search(query_vector)
            .where(f"category = '{category_en}'")
            .limit(top_k)
            .to_list()
        )
    except Exception as exc:
        detail = str(exc)
        if "dimension" in detail.lower() or "shape" in detail.lower():
            user_msg = (
                "پایگاه دانش با نسخه دیگری از مدل ساخته شده و با نسخه فعلی سازگار نیست. "
                "لازم است پایگاه دانش دوباره ساخته شود."
            )
        else:
            user_msg = "جستجو در پایگاه دانش با خطا مواجه شد."
        raise RetrievalError(user_msg, f"vector search failed: {detail}") from exc

    # --- ۵. ترکیب نتایج ------------------------------------------------
    if not results:
        return ""

    chunks = [r.get("text", "") for r in results if r.get("text")]
    return "\n\n---\n\n".join(chunks)


# ===========================================================================
# ساخت پرامپت
# ===========================================================================
_SYSTEM_PREAMBLE = (
    "شما یک دستیار هوش مصنوعی مستقل برای مدیریت بحران و شرایط اضطراری هستید "
    "(همیار نجات آفلاین).\n"
    "لطفاً تنها با استفاده از اطلاعات مرجع زیر به سوال کاربر پاسخ دقیق و کاربردی بدهید.\n"
    "اگر پاسخ در اطلاعات مرجع وجود نداشت، راهنمایی‌های کلی و ایمن ارائه دهید "
    "اما حتماً ذکر کنید که این بخش از اطلاعات در پایگاه داده تخصصی شما نیست."
)


def _build_prompt(query: str, context: str, history_messages: list = None) -> str:
    """ساخت پرامپت واحد برای هر دو حالت invoke و stream."""
    parts = [_SYSTEM_PREAMBLE, ""]

    if context:
        parts.append("اطلاعات مرجع:")
        parts.append(context)
    else:
        parts.append("اطلاعات مرجع: (موردی در پایگاه دانش یافت نشد)")
    parts.append("")

    if history_messages:
        # فقط چند نوبت آخر نگه داشته می‌شود تا پنجره متن مدل پر نشود.
        recent = history_messages[-6:]
        parts.append("تاریخچه مکالمه:")
        for msg in recent:
            role_fa = "کاربر" if msg.get("role") == "user" else "دستیار"
            parts.append(f"{role_fa}: {msg.get('content', '')}")
        parts.append("")

    parts.append(f"سوال کاربر: {query}")
    parts.append("پاسخ:")
    return "\n".join(parts)


# ===========================================================================
# تولید پاسخ - حالت جریانی (streaming)
# ===========================================================================
def stream_response_with_history(query: str, context: str, history_messages: list = None):
    """
    تولید پاسخ به صورت جریانی. هر قطعه متن به محض آماده شدن بازگردانده می‌شود.

    استفاده:
        for token in stream_response_with_history(q, ctx, hist):
            ...

    دلیل اهمیت: روی سخت‌افزار بدون کارت گرافیک، یک مدل ۸ میلیاردی ممکن است
    ۳۰ تا ۱۲۰ ثانیه طول بکشد. نمایش تدریجی متن باعث می‌شود کاربر بداند سامانه
    کار می‌کند — که در شرایط اضطراری اهمیت زیادی دارد.

    استثنا: GenerationError
    """
    prompt = _build_prompt(query, context, history_messages)

    try:
        llm = get_llm()
    except Exception as exc:
        raise GenerationError(
            "موتور محلی هوش مصنوعی در دسترس نیست.",
            f"get_llm failed: {exc}",
        ) from exc

    try:
        for chunk in llm.stream(prompt):
            # بسته به نسخه langchain، خروجی می‌تواند رشته یا شیء باشد.
            if chunk is None:
                continue
            text = chunk if isinstance(chunk, str) else getattr(chunk, "content", str(chunk))
            if text:
                yield text
    except Exception as exc:
        raise GenerationError(
            "تولید پاسخ توسط مدل زبانی با خطا مواجه شد. "
            "لطفاً دوباره تلاش کنید.",
            f"llm.stream failed: {exc}",
        ) from exc


# ===========================================================================
# تولید پاسخ - حالت یکجا (سازگاری با کد قدیمی)
# ===========================================================================
def generate_response_with_history(query: str, context: str, history_messages: list = None) -> str:
    """نسخه غیرجریانی. برای سازگاری با کدهای قبلی نگه داشته شده است."""
    return "".join(stream_response_with_history(query, context, history_messages))


def generate_response(query: str, context: str) -> str:
    """نسخه بدون تاریخچه."""
    return generate_response_with_history(query, context, None)
