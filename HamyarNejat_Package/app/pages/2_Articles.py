import streamlit as st
import os
import sys

current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
if parent_dir not in sys.path:
    sys.path.insert(0, parent_dir)

from core.ui_utils import setup_custom_sidebar, get_base64_of_bin_file

def inject_articles_css():
    st.markdown("""
    <style>
        /* راست‌چین کردن لیبل دراپ‌داون */
        [data-testid="stSelectbox"] label {
            direction: rtl !important;
            text-align: right !important;
            width: 100% !important;
            display: block !important;
        }

        /* راست‌چین کردن متن داخل خود باکس دراپ‌داون */
        [data-testid="stSelectbox"] div[data-baseweb="select"] {
            direction: rtl !important;
            text-align: right !important;
        }
        
        /* راست‌چین کردن قطعی لیست‌های نقطه‌ای و عددی در مقالات */
        [data-testid="stMarkdownContainer"] ul, 
        [data-testid="stMarkdownContainer"] ol, 
        [data-testid="stMarkdownContainer"] li {
            direction: rtl !important;
            text-align: right !important;
            padding-right: 20px !important; /* برای ایجاد فاصله مناسب بولت‌ها از سمت راست */
        }  
        
        @import url('https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/Vazirmatn-font-face.css');
        html, body, p, div, h1, h2, h3, h4, h5, h6, a, button, input, textarea, select {
            font-family: 'Vazirmatn', sans-serif !important;
        }
        .material-symbols-rounded, 
        span[class*="material-symbols"] {
            font-family: 'Material Symbols Rounded' !important;
        }
        [data-testid="stSidebarNav"] { display: none !important; }
        [data-testid="stSidebarUserContent"] { direction: rtl; text-align: right; }
        [data-testid="stMarkdownContainer"], [data-testid="stText"] { 
            direction: rtl; 
            text-align: right; 
        }
        .stDeployButton { display: none !important; }
        
        /* Footer Pin */
        .offline-footer {
            position: fixed;
            bottom: 0;
            left: 0;
            width: 100%;
            background-color: #f0f2f6;
            color: #31333F;
            border-top: 1px solid #e0e0e0;
            text-align: center;
            padding: 10px;
            font-size: 14px;
            z-index: 1000;
        }
        .block-container {
            padding-bottom: 80px !important;
        }
        /* Inline Header styling */
        .header-container {
            display: flex;
            align-items: center;
            justify-content: flex-start;
            direction: rtl;
            margin-bottom: 20px;
        }
        .header-container img {
            width: 80px;
            height: 80px;
            border-radius: 50%;
            margin-left: 15px;
            object-fit: cover;
            background-color: transparent;
        }
        .header-container h1 {
            margin: 0;
            padding: 0;
            font-size: 2.5rem;
            line-height: 1.2;
        }
    </style>
    """, unsafe_allow_html=True)

logo_path = os.path.join(parent_dir, "assets", "images", "logo.png")
st.set_page_config(page_title="مقالات فوریت‌های پزشکی", page_icon=logo_path, layout="centered")
setup_custom_sidebar()
inject_articles_css()

# Pinned Footer
st.markdown("""
    <div class="offline-footer">
        این سیستم کاملاً آفلاین اجرا می‌شود و هیچ داده‌ای به خارج از این کامپیوتر ارسال نمی‌گردد.
    </div>
""", unsafe_allow_html=True)

logo_b64 = get_base64_of_bin_file(logo_path)
img_tag = f'<img src="data:image/png;base64,{logo_b64}" alt="Logo">' if logo_b64 else ""

st.markdown(f"""
<div class="header-container">
    {img_tag}
    <h1>همیار نجات آفلاین</h1>
</div>
""", unsafe_allow_html=True)

articles_icon_path = os.path.join(parent_dir, "assets", "images", "icon_articles.png")
articles_b64 = get_base64_of_bin_file(articles_icon_path)
icon_html = f'<img src="data:image/png;base64,{articles_b64}" style="width: 40px; margin-left: 10px;">' if articles_b64 else ""

st.markdown(f"""
<div style="display: flex; align-items: center; justify-content: flex-start; direction: rtl; margin-bottom: 20px;">
    {icon_html}
    <h1 style="margin: 0; padding: 0;">مقالات فوریت‌های پزشکی</h1>
</div>
""", unsafe_allow_html=True)

st.write("در این بخش می‌توانید به صورت مستقیم و بدون هوش مصنوعی به دستورالعمل‌های حیاتی پزشکی دسترسی داشته باشید.")
st.divider()

from core.config import ARTICLES_DIR
knowledge_dir = ARTICLES_DIR

def get_article_mappings(directory):
    mappings = {}
    if os.path.exists(directory):
        for f in os.listdir(directory):
            if f.endswith('.md'):
                file_path = os.path.join(directory, f)
                try:
                    with open(file_path, 'r', encoding='utf-8') as file:
                        first_line = file.readline()
                        title = first_line.strip().lstrip('#').strip()
                        if not title:
                            title = f  # Fallback if first line is empty or no text
                        mappings[title] = file_path
                except Exception:
                    mappings[f] = file_path # Fallback on error
    return mappings

mappings = get_article_mappings(knowledge_dir)

if not mappings:
    st.warning("هیچ مقاله‌ای در پوشه Articles یافت نشد.")
else:
    titles = list(mappings.keys())
    # Sort titles if needed, or leave them as is
    # titles.sort()
    selected_title = st.selectbox("یک مقاله را انتخاب کنید:", titles)
    
    st.divider()
    if selected_title:
        file_path = mappings[selected_title]
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            st.markdown(content)