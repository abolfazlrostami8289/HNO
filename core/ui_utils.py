import streamlit as st
import os
import base64

def get_base64_of_bin_file(bin_file):
    if os.path.exists(bin_file):
        with open(bin_file, 'rb') as f:
            data = f.read()
        return base64.b64encode(data).decode()
    return ""

def setup_custom_sidebar():
    base_dir = os.path.dirname(os.path.dirname(__file__))
    
    logo_path = os.path.join(base_dir, "logo.png")
    home_icon_path = os.path.join(base_dir, "icon_home.png")
    chat_icon_path = os.path.join(base_dir, "icon_chat.png")
    articles_icon_path = os.path.join(base_dir, "icon_articles.png")
    # اصلاح مسیر: حالا دقیقاً در روت پروژه دنبال عکس می‌گردد
    sidebar_icon_path = os.path.join(base_dir, "icon_sidebar_opened.png")
    
    logo_b64 = get_base64_of_bin_file(logo_path)
    home_b64 = get_base64_of_bin_file(home_icon_path)
    chat_b64 = get_base64_of_bin_file(chat_icon_path)
    articles_b64 = get_base64_of_bin_file(articles_icon_path)
    
    sidebar_icon_b64 = get_base64_of_bin_file(sidebar_icon_path)
    sidebar_icon_mime = "image/png"
    
    if not sidebar_icon_b64:
        # Fallback SVG if PNG is not found
        fallback_svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#666666" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="3" y1="12" x2="21" y2="12"></line><line x1="3" y1="6" x2="21" y2="6"></line><line x1="3" y1="18" x2="21" y2="18"></line></svg>'
        sidebar_icon_b64 = base64.b64encode(fallback_svg.encode('utf-8')).decode('utf-8')
        sidebar_icon_mime = "image/svg+xml"
    
    st.markdown(f"""
        <style>
        /* ایمپورت قطعی فونت وزیرمتن برای استفاده در کل سایدبار */
        @import url('https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/Vazirmatn-font-face.css');
        
        /* مخفی‌سازی منوی پیش‌فرض */
        [data-testid="stSidebarNav"] {{ 
            display: none !important; 
        }}
        
        /* تنظیم فونت کل سایدبار */
        [data-testid="stSidebar"], [data-testid="stSidebar"] * {{
            font-family: 'Vazirmatn', tahoma, sans-serif !important;
        }}
        
        /* مخفی کردن آیکون‌های پیش‌فرض دکمه‌های باز و بسته کردن سایدبار */
        [data-testid="collapsedControl"] > *,
        [data-testid="stSidebarCollapseButton"] > * {{
            display: none !important;
        }}
        
        /* تزریق آیکون سفارشی سایدبار */
        [data-testid="collapsedControl"]::before,
        [data-testid="stSidebarCollapseButton"]::before {{
            content: "";
            display: block; /* changed from inline-block to block */
            width: 28px;
            height: 28px;
            background-image: url("data:{sidebar_icon_mime};base64,{sidebar_icon_b64}");
            background-size: contain;
            background-repeat: no-repeat;
            background-position: center;
            cursor: pointer;
        }}
        
        /* چرخش فلش برای حالت بسته شدن (collapsed) */
        [data-testid="collapsedControl"]::before {{
            transform: rotate(180deg);
        }}
        
        .custom-sidebar-container {{
            direction: rtl;
            text-align: right;
            padding: 10px 0;
            margin-bottom: 20px;
        }}
        
        .custom-sidebar-logo {{
            text-align: center;
            margin-bottom: 40px;
        }}
        
        .custom-sidebar-logo img {{
            width: 150px;
            height: auto;
            border-radius: 10px;
            background-color: transparent;
        }}
        
        /* هدف قرار دادن تگ a در تمام حالت‌ها برای جلوگیری از آبی شدن */
        a.custom-sidebar-link, 
        a.custom-sidebar-link:visited, 
        a.custom-sidebar-link:active {{
            display: flex !important;
            align-items: center !important;
            justify-content: flex-start !important;
            text-decoration: none !important;
            color: var(--text-color) !important;
            font-size: 1.3rem !important; 
            margin-bottom: 25px !important; 
            padding: 10px 15px !important;
            border-radius: 8px !important;
            transition: background-color 0.3s !important;
            font-family: 'Vazirmatn', tahoma, sans-serif !important;
        }}
        
        a.custom-sidebar-link:hover {{
            background-color: rgba(128, 128, 128, 0.2) !important;
            color: var(--text-color) !important;
        }}
        
        .custom-sidebar-link img {{
            width: 32px;
            height: 32px;
            margin-left: 15px !important;
        }}
        </style>
    """, unsafe_allow_html=True)
    
    def get_img_tag(b64, alt):
        if b64:
            return f'<img src="data:image/png;base64,{b64}" alt="{alt}">'
        return f'<span style="margin-left: 15px; font-size: 1.5rem;">🔹</span>'
        
    logo_tag = f'<img src="data:image/png;base64,{logo_b64}" alt="Logo">' if logo_b64 else ""
    home_tag = get_img_tag(home_b64, "Home")
    chat_tag = get_img_tag(chat_b64, "Chat")
    articles_tag = get_img_tag(articles_b64, "Articles")
    
    sidebar_html = f"""
    <div class="custom-sidebar-container">
        <div class="custom-sidebar-logo">
            {logo_tag}
        </div>
        <a href="/" target="_self" class="custom-sidebar-link">
            {home_tag}
            <span>صفحه اصلی</span>
        </a>
        <a href="/Chat" target="_self" class="custom-sidebar-link">
            {chat_tag}
            <span>همیار چت</span>
        </a>
        <a href="/Articles" target="_self" class="custom-sidebar-link">
            {articles_tag}
            <span>مقالات آموزشی</span>
        </a>
    </div>
    """
    
    st.sidebar.markdown(sidebar_html, unsafe_allow_html=True)