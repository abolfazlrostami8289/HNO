import streamlit as st
import os
import base64

def get_base64_of_bin_file(bin_file):
    if os.path.exists(bin_file):
        with open(bin_file, 'rb') as f:
            data = f.read()
        return base64.b64encode(data).decode()
    return ""

logo_path = os.path.join(os.path.dirname(__file__), "logo.png")

st.set_page_config(
    page_title="همیار نجات آفلاین",
    page_icon="logo.png",
    layout="centered"
)

def inject_custom_css():
    st.markdown("""
    <style>
        @import url('https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/Vazirmatn-font-face.css');
        html, body, p, div, h1, h2, h3, h4, h5, h6, a, button, input, textarea, select {
            font-family: 'Vazirmatn', sans-serif;
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
        .stDeployButton {
            display: none !important;
        }
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
        /* Button text centering and truncation */
        .stButton button {
            width: 100%;
        }
        .single-line-text {
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            text-align: center;
            margin-bottom: 15px;
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

inject_custom_css()

# Custom Logo handling instead of Emoji
logo_base64 = get_base64_of_bin_file(logo_path)
if logo_base64:
    img_tag = f'<img src="data:image/png;base64,{logo_base64}" alt="Logo" style="background-color: transparent;">'
else:
    img_tag = ""

st.markdown(f"""
<div class="header-container">
    {img_tag}
    <h1>همیار نجات آفلاین</h1>
</div>
""", unsafe_allow_html=True)

st.markdown("""
<div style="text-align: right; direction: rtl; font-size: 1.1rem; margin-bottom: 20px;">
    به سیستم هوش مصنوعی امداد و نجات آفلاین خوش آمدید. 
    این سامانه کاملاً مستقل از اینترنت بوده و برای ارائه مشاوره‌های حیاتی در شرایط بحرانی طراحی شده است.
</div>
""", unsafe_allow_html=True)

with st.sidebar:
    st.page_link("app.py", label="صفحه اصلی", icon="🏠")
    st.page_link("pages/1_Chat.py", label="چت بات", icon="💬")
    st.page_link("pages/2_Articles.py", label="مقالات", icon="📚")

st.divider()

col1, col2 = st.columns(2)

with col1:
    st.info("💬 چت با هوش مصنوعی")
    st.markdown("<div class='single-line-text'>دریافت مشاوره افلاین از هوش مصنوعی</div>", unsafe_allow_html=True)
    if st.button("ورود به چت", use_container_width=True):
        st.switch_page("pages/1_Chat.py")

with col2:
    st.success("📚 مقالات پزشکی")
    st.markdown("<div class='single-line-text'>مطالعه دستور العمل های پزشکی و حیاتی</div>", unsafe_allow_html=True)
    if st.button("مشاهده مقالات", use_container_width=True):
        st.switch_page("pages/2_Articles.py")

# Pinned Footer message
st.markdown("""
    <div class="offline-footer">
        این سیستم کاملاً آفلاین اجرا می‌شود و هیچ داده‌ای به خارج از این کامپیوتر ارسال نمی‌گردد.
    </div>
""", unsafe_allow_html=True)
