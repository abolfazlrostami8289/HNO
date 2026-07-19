import os
import lancedb
from langchain_community.embeddings import OllamaEmbeddings
from langchain_text_splitters import MarkdownHeaderTextSplitter, RecursiveCharacterTextSplitter

# تعیین مسیرها
BASE_DIR = os.path.dirname(os.path.dirname(__file__))
DB_PATH = os.path.join(BASE_DIR, "lancedb_data")
ARTICLES_DIR = os.path.join(BASE_DIR, "knowledge-files")
for filename in os.listdir(ARTICLES_DIR):
    if filename.endswith(".md"): # این شرط حیاتی است تا به بقیه فایل‌ها گیر ندهد
        file_path = os.path.join(ARTICLES_DIR, filename)
        # ... ادامه پردازش

def get_embeddings_model():
    """Returns the local Ollama embedding model."""
    return OllamaEmbeddings(model="bge-m3")

def chunk_markdown_with_metadata(file_path: str):
    """
    استخراج متادیتای YAML به صورت دستی و Chunking بر اساس ساختار Markdown
    """
    with open(file_path, 'r', encoding='utf-8-sig') as f:
        lines = f.readlines()
    
    metadata = {}
    content_lines = []
    in_yaml = False
    
    # پردازش خط به خط برای پیدا کردن بلاک YAML
    for line in lines:
        stripped = line.strip()
        if stripped == "---":
            in_yaml = not in_yaml
            continue
        
        if in_yaml and ":" in line:
            key, val = line.split(":", 1)
            # تمیز کردن مقادیر (حذف کوتیشن‌ها و براکت‌های اضافی)
            metadata[key.strip()] = val.strip().replace('"', '').replace("'", "").replace("[", "").replace("]", "")
        elif not in_yaml:
            content_lines.append(line)
            
    content = "".join(content_lines)
    
    # بخش Chunking همان‌طور که نیاز داشتی
    from langchain_text_splitters import MarkdownHeaderTextSplitter, RecursiveCharacterTextSplitter
    
    headers_to_split_on = [("#", "Header 1"), ("##", "Header 2"), ("###", "Header 3")]
    markdown_splitter = MarkdownHeaderTextSplitter(headers_to_split_on=headers_to_split_on)
    md_chunks = markdown_splitter.split_text(content)
    
    text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=150)
    final_chunks = text_splitter.split_documents(md_chunks)
    
    # تزریق متادیتای استخراج شده به Chunkها برای استفاده در LanceDB
    for chunk in final_chunks:
        chunk.metadata['category'] = metadata.get('category', 'general')
        chunk.metadata['subcategory'] = metadata.get('subcategory', 'general')
        chunk.metadata['source'] = os.path.basename(file_path)
        
    return final_chunks

def ingest_all():
    """
    خواندن مقالات، تولید وکتور و ذخیره در یک جدول یکپارچه همراه با فیلتر متادیتا
    """
    print("Starting Ingestion Process...")
    db = lancedb.connect(DB_PATH)
    embedder = get_embeddings_model()
    table_name = "knowledge_base" # جدول یکپارچه
    
    if not os.path.exists(ARTICLES_DIR):
        print(f"Error: Articles folder not found at {ARTICLES_DIR}")
        return
        
    all_chunks = []
    
    # خواندن تمام فایل‌های مارک‌داون
    for filename in os.listdir(ARTICLES_DIR):
        if filename.endswith(".md"):
            file_path = os.path.join(ARTICLES_DIR, filename)
            chunks = chunk_markdown_with_metadata(file_path)
            all_chunks.extend(chunks)
            
    if not all_chunks:
        print("No valid chunks found to ingest.")
        return

    print(f"Generating embeddings for {len(all_chunks)} chunks using bge-m3...")
    
    # تولید وکتور برای تمام تکه‌ها
    texts = [chunk.page_content for chunk in all_chunks]
    embeddings = embedder.embed_documents(texts)
    
    # آماده‌سازی دیتا برای دیتابیس (شامل ستون‌های متادیتا برای فیلتر کردن)
    data = []
    for i, chunk in enumerate(all_chunks):
        # اضافه کردن هدینگ‌ها به اول متن برای حفظ کانتکست
        headers_context = " | ".join([f"{k}: {v}" for k, v in chunk.metadata.items() if k.startswith("Header")])
        full_text = f"{headers_context}\n\n{chunk.page_content}" if headers_context else chunk.page_content
        
        data.append({
            "vector": embeddings[i],
            "text": full_text,
            "category": chunk.metadata['category'],
            "subcategory": chunk.metadata['subcategory'],
            "source": chunk.metadata['source']
        })
        
    # رفرش کردن جدول اگر از قبل وجود داشت
    if table_name in db.table_names():
        db.drop_table(table_name)
        
    db.create_table(table_name, data=data)
    print(f"Successfully created LanceDB table '{table_name}' with {len(data)} records.")
    print("Ingestion Process Completed.")

if __name__ == "__main__":
    ingest_all()