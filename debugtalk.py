from dynaconf import settings
import random
import re
from transformers import AutoTokenizer

def os_env(ekey, default=""):
    "提取环境配置变量"
    """字典get()方法
    get()方法用于根据指定的键获取元素的值。
    语法：
    dictionary_name.fromkeys(keys, value)
    Parameter(s)：
    key –它代表要返回其值的键的名称。
    value –这是一个可选参数，用于指定如果项目不存在则返回的值。"""
    return settings.get(ekey,default)

def stop_text(text,stop):
    return text.split(stop)[0]

def remove_model_words(res):
    print('*'*50,res)
    if "<think>\n</think>" in res:
        return res.split("<think>\n</think>")[1]
    # elif "<think></think>" in res:
    #     return res.split("<think></think>")[1]
    else:
        return res

def get_stop_token_ids(content,model):
    words = content.split()
    # 去除标点符号（可选）
    clean_words = []
    for word in words:
        # 移除单词两端的标点符号
        clean_word = word.strip('.,!?;:"\'()[]{}')
        if clean_word:  # 确保不是空字符串
            clean_words.append(clean_word.lower())  # 转为小写以确保唯一性
        # 确保有至少3个不同的单词
    unique_words = list(set(clean_words))
    if len(unique_words) < 3:
        raise ValueError("文本中需要至少3个不同的单词")
    
    # 随机选择3个不同的单词
    selected_words = random.sample(unique_words, 3)
    print(model)
    tokenizer = AutoTokenizer.from_pretrained(model, trust_remote_code=True)
    token_ids=[]
    words=[]
    for word in selected_words:
        tokenid = tokenizer.encode(word)
        token_id=''
        if len(tokenid)==1:
            token_id=tokenid[0]
        elif len(tokenid)==2:
            token_id=tokenid[1]
        if token_id !='':
            token_ids.append(token_id)
            words.append(word)
        print('*'*25 + 'debugtalk' +'*'*25,selected_words)
        print('*'*25 + 'debugtalk' +'*'*25,token_ids)
        
    return words,token_ids
    # return ['level', 'changed'],[3294, 17353]