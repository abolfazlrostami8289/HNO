import re

# List of conversational stop words to be removed
STOP_WORDS = [
    "سلام", "خوبی", "لطفا", "لطفاً", "میشه بگید", "یه سوال داشتم", "میشه بگی", 
    "چطوری", "کمک", "میخوام بدونم", "سوال", "جواب بده", "آیا", "چگونه", 
    "میتونی", "میتونید", "درود", "خسته نباشید"
]

def normalize_persian(text: str) -> str:
    """
    Normalizes Persian characters and removes zero-width spaces.
    """
    # Replace Arabic characters with Persian equivalents
    text = text.replace('ي', 'ی').replace('ك', 'ک').replace('ة', 'ه')
    # Remove Zero-Width Non-Joiner (ZWNJ)
    text = text.replace('\u200c', ' ')
    # Normalize multiple spaces
    text = re.sub(r'\s+', ' ', text)
    return text.strip()

def remove_stop_words(text: str) -> str:
    """
    Removes conversational noise and stop words from the query.
    """
    res = text
    
    # First, handle multi-word phrases
    for phrase in STOP_WORDS:
        if " " in phrase:
            res = res.replace(phrase, "")
            
    # Then handle single words
    words = res.split()
    filtered_words = [word for word in words if word not in STOP_WORDS]
    
    # Reconstruct the text
    res = " ".join(filtered_words)
    res = re.sub(r'\s+', ' ', res).strip()
    return res

def inject_implicit_context(text: str) -> str:
    """
    Injects implicit context invisibly to the user query for better retrieval.
    """
    return text + " تهران شرایط اضطراری آفلاین"

def preprocess_query(query: str) -> str:
    """
    Executes the full preprocessing pipeline.
    """
    normalized = normalize_persian(query)
    no_stops = remove_stop_words(normalized)
    final_query = inject_implicit_context(no_stops)
    return final_query
