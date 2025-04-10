from dynaconf import settings

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
    