import os
import lancedb
from langchain_community.embeddings import OllamaEmbeddings
from langchain_community.llms import Ollama

DB_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "lancedb_data")

# تبدیل لیبل‌های رابط کاربری به مقادیر category در YAML متادیتا
CATEGORY_MAPPING = {
    "فوریت‌های پزشکی": "medical_emergency",
    "فوریت‌های فنی": "technical_emergency",
    "فوریت‌های روانشناسی": "psychological_emergency",
    "فوریت‌های امدادی": "rescue_emergency"
}

def retrieve_context(query: str, category: str, top_k: int = 3) -> str:
    """
    واکشی اطلاعات با استفاده از فیلتر متادیتا (Pre-filtering)
    """
    category_en = CATEGORY_MAPPING.get(category)
    if not category_en:
        return ""
        
    db = lancedb.connect(DB_PATH)
    table_name = "knowledge_base"
    
    if table_name not in db.table_names():
        return "پایگاه داده یافت نشد. لطفاً ابتدا فایل ingest.py را اجرا کنید."
        
    table = db.open_table(table_name)
    embedder = OllamaEmbeddings(model="bge-m3:latest")
    
    # تبدیل سوال کاربر به وکتور
    query_vector = embedder.embed_query(query)
    
    try:
        # جستجوی برداری + فیلتر محدودکننده (فقط در همان دسته بگرد)
        results = table.search(query_vector).where(f"category = '{category_en}'").limit(top_k).to_list()
    except Exception as e:
        print(f"Error during retrieval: {e}")
        return ""
    
    # ترکیب تکه‌های یافت‌شده
    context = "\n\n---\n\n".join([res['text'] for res in results])
    return context

def generate_response(query: str, context: str) -> str:
    """
    Generates a response using the locally hosted LLM based on the retrieved context.
    """
    llm = Ollama(model="aya-expanse:8b")
    
    prompt = f"""شما یک دستیار هوش مصنوعی مستقل برای مدیریت بحران و شرایط اضطراری هستید (همیار نجات آفلاین). 
لطفاً تنها با استفاده از اطلاعات مرجع زیر به سوال کاربر پاسخ دقیق و کاربردی بدهید.
اگر پاسخ در اطلاعات مرجع وجود نداشت، راهنمایی‌های کلی و ایمن ارائه دهید اما حتماً ذکر کنید که این بخش از اطلاعات در پایگاه داده تخصصی شما نیست.

اطلاعات مرجع:
{context}

سوال کاربر: {query}

پاسخ:"""
    
    response = llm.invoke(prompt)
    return response

def generate_response_with_history(query: str, context: str, history_messages: list) -> str:
    """
    Generates a response using the local LLM, utilizing conversation history.
    """
    llm = Ollama(model="aya-expanse:8b")
    
    # Format history
    history_str = ""
    for msg in history_messages:
        role_fa = "کاربر" if msg["role"] == "user" else "دستیار"
        history_str += f"{role_fa}: {msg['content']}\n"
        
    prompt = f"""شما یک دستیار هوش مصنوعی مستقل برای مدیریت بحران و شرایط اضطراری هستید (همیار نجات آفلاین). 
لطفاً تنها با استفاده از اطلاعات مرجع زیر و تاریخچه مکالمه به سوال کاربر پاسخ دقیق و کاربردی بدهید.
اگر پاسخ در اطلاعات مرجع وجود نداشت، راهنمایی‌های کلی و ایمن ارائه دهید اما حتماً ذکر کنید که این بخش از اطلاعات در پایگاه داده تخصصی شما نیست.

اطلاعات مرجع:
{context}

تاریخچه مکالمه:
{history_str}

سوال کاربر: {query}
پاسخ:"""
    
    response = llm.invoke(prompt)
    return response
