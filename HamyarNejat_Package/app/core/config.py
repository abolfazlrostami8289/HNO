"""
پیکربندی مرکزی همیار نجات
--------------------------------------------------------------------------
تمام نام مدل‌ها، مسیرها و تنظیمات اتصال به Ollama فقط در همین فایل تعریف
می‌شوند. هیچ ماژول دیگری نباید نام مدل را به صورت رشته ثابت بنویسد.

دلیل: پیش از این ingest.py و retrieve.py هر کدام نام مدل embedding را جداگانه
تعریف کرده بودند ("bge-m3" در برابر "bge-m3:latest"). اگر این دو با هم فرق
کنند، بردارهای ساخته‌شده در زمان ingest با بردار پرسش هم‌بعد نخواهند بود و
جستجو با خطا شکست می‌خورد — خطایی که در retrieve.py گرفته و نادیده گرفته
می‌شد، پس کاربر هرگز متوجه نمی‌شد که بازیابی اطلاعات کار نکرده است.

مسیر این فایل: HamyarNejat_Package/app/core/config.py
"""

import os

# ---------------------------------------------------------------------------
# مسیرها
# BASE_DIR = HamyarNejat_Package/app
# ---------------------------------------------------------------------------
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DB_PATH = os.path.join(BASE_DIR, "lancedb_data")
KNOWLEDGE_DIR = os.path.join(BASE_DIR, "knowledge-files")
HISTORY_FILE = os.path.join(BASE_DIR, "chat_history.json")

TABLE_NAME = "knowledge_base"

# ---------------------------------------------------------------------------
# مدل‌ها — تنها محل تعریف
# این نام‌ها باید دقیقاً با خروجی `ollama list` و با آرایه RequiredModels در
# run.ps1 یکسان باشند.
# ---------------------------------------------------------------------------
EMBED_MODEL = "bge-m3"
LLM_MODEL = "aya-expanse:8b"

# ---------------------------------------------------------------------------
# اتصال به Ollama
# از 127.0.0.1 استفاده می‌شود نه localhost: در ویندوز localhost ممکن است ابتدا
# به ::1 ترجمه شود در حالی که سرور روی IPv4 گوش می‌دهد.
# run.ps1 متغیر OLLAMA_HOST را تنظیم می‌کند؛ اینجا فقط آن را می‌خوانیم.
# ---------------------------------------------------------------------------
_raw_host = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434").strip()
if _raw_host.startswith("http://") or _raw_host.startswith("https://"):
    OLLAMA_BASE_URL = _raw_host.rstrip("/")
else:
    OLLAMA_BASE_URL = f"http://{_raw_host}"

# اندازه پنجره متن. aya-expanse از 8192 پشتیبانی می‌کند.
NUM_CTX = 8192
TEMPERATURE = 0.2

RETRIEVAL_TOP_K = 3

# نگاشت برچسب‌های رابط کاربری به مقدار category در متادیتای YAML
CATEGORY_MAPPING = {
    "فوریت‌های پزشکی": "medical_emergency",
    "فوریت‌های فنی": "technical_emergency",
    "فوریت‌های روانشناسی": "psychological_emergency",
    "فوریت‌های امدادی": "rescue_emergency",
}


def get_embedder():
    """
    ساخت مدل embedding. هم ingest و هم retrieve باید از همین تابع استفاده کنند
    تا امکان ناهماهنگی بین آن دو از بین برود.
    """
    from langchain_community.embeddings import OllamaEmbeddings

    return OllamaEmbeddings(
        model=EMBED_MODEL,
        base_url=OLLAMA_BASE_URL,
    )


def get_llm():
    """ساخت مدل زبانی با تنظیمات یکسان در تمام برنامه."""
    from langchain_community.llms import Ollama

    return Ollama(
        model=LLM_MODEL,
        base_url=OLLAMA_BASE_URL,
        temperature=TEMPERATURE,
        num_ctx=NUM_CTX,
    )


def check_ollama_ready(timeout: float = 3.0):
    """
    بررسی در دسترس بودن Ollama و موجود بودن مدل‌های لازم.

    خروجی: (ok: bool, message: str)

    این تابع برای نمایش وضعیت در نوار کناری استفاده می‌شود تا اگر موتور محلی
    خاموش باشد، کاربر به جای یک traceback انگلیسی، پیام فارسی روشن ببیند.
    """
    import json
    import urllib.request

    try:
        with urllib.request.urlopen(f"{OLLAMA_BASE_URL}/api/tags", timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception:
        return False, "موتور محلی هوش مصنوعی در دسترس نیست. لطفاً برنامه را ببندید و دوباره اجرا کنید."

    available = [m.get("name", "") for m in data.get("models", [])]

    missing = []
    for needed in (EMBED_MODEL, LLM_MODEL):
        bare = needed.split(":")[0]
        if not any(name == needed or name.startswith(bare + ":") for name in available):
            missing.append(needed)

    if missing:
        return False, "مدل‌های زبانی زیر یافت نشدند: " + "، ".join(missing)

    return True, "آماده"
