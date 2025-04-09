import os
from openai import OpenAI
import pytest
from openai.types.chat import ChatCompletionChunk,ChatCompletion
from openai import Stream
import openai
import allure

def stop_text(text,stop):
    return text.split(stop)[0]

client = OpenAI(
    # This is the default and can be omitted
    api_key="-",
    base_url="http://10.208.130.44:2025/v1"
)
model = "deepseek"

@pytest.fixture
@allure.title("对话_判断stream为false时，返回为ChatCompletion类型")
def test_not_stream_chat():
    # 判断stream为false时，返回为ChatCompletion类型
    completion = client.chat.completions.create(
        model=model,
        messages=[
        {
            "role": "developer",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "Hello!"
        }
        ],
        temperature=0,
        stream=False,
    )
    assert isinstance(completion, ChatCompletion) == True
    assert completion.choices[0].message.role == 'assistant'
    no_stop_content = completion.choices[0].message.content
    no_stop_tokens = completion.usage.completion_tokens
    print(no_stop_content)
    return no_stop_content,no_stop_tokens
    
@allure.title("对话_判断设置max_tokens时，输出文本最长为max_tokens，stop reason为length")
def test_not_stream_with_max_tokens(test_not_stream_chat):
    max_tokens = 6
    # 判断max_tokens参数生效
    completion = client.chat.completions.create(
        model=model,
        messages=[
        {
            "role": "developer",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "Hello!"
        }
        ],
        temperature=0,
        max_tokens=max_tokens
    )
    assert isinstance(completion, ChatCompletion) == True
    assert test_not_stream_chat[0] != completion.choices[0].message.content
    assert test_not_stream_chat[1] > completion.usage.completion_tokens
    assert completion.usage.completion_tokens == max_tokens
    assert completion.choices[0].finish_reason == 'length'
    
@allure.title("对话_判断设置max_completion_tokens时，输出文本最长为max_completion_tokens，stop reason为length")
def test_not_stream_with_max_completion_tokens(test_not_stream_chat):
    max_completion_tokens = 6
    # 判断max_tokens参数生效
    completion = client.chat.completions.create(
        model=model,
        messages=[
        {
            "role": "developer",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "Hello!"
        }
        ],
        temperature=0,
        max_completion_tokens=max_completion_tokens
    )
    assert isinstance(completion, ChatCompletion) == True
    assert test_not_stream_chat[0] != completion.choices[0].message.content
    assert test_not_stream_chat[1] > completion.usage.completion_tokens
    assert completion.usage.completion_tokens == max_completion_tokens
    assert completion.choices[0].finish_reason == 'length'
    
@allure.title("对话_判断设置max_completion_tokens != max_tokens时，400报错，返回正确提示信息")    
def test_max_tokens_not_equal_max_completion_tokens():
    max_completion_tokens = 6
    # 判断max_tokens和max_completion_tokens不一致时提示信息正确
    try:
        client.chat.completions.create(
            model=model,
            messages=[
            {
                "role": "developer",
                "content": "You are a helpful assistant."
            },
            {
                "role": "user",
                "content": "Hello!"
            }
            ],
            temperature=0,
            max_completion_tokens=max_completion_tokens,
            max_tokens=max_completion_tokens + 1
            
        )
    except openai.BadRequestError as e:
        assert e.status_code == 400
        assert 'max_tokens and max_completion_tokens cannot have different values.' in e.message

@allure.title("对话_判断设置max_completion_tokens == max_tokens时，返回正确信息")    
def test_max_tokens_equal_max_completion_tokens():
    max_completion_tokens = 6
    # 判断max_tokens和max_completion_tokens不一致时提示信息正确
    completion = client.chat.completions.create(
        model=model,
        messages=[
        {
            "role": "developer",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "Hello!"
        }
        ],
        temperature=0,
        max_completion_tokens=max_completion_tokens,
        max_tokens=max_completion_tokens   
    )
    assert isinstance(completion, ChatCompletion) == True
    assert completion.usage.completion_tokens == max_completion_tokens
    assert completion.choices[0].finish_reason == 'length'
        
@allure.title("对话_不设置max_completion_tokens时，使用束搜索")   
def test_with_beam_search_without_max_tokens():
    completion = client.chat.completions.create(
        model=model,
        messages=[
        {
            "role": "developer",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "Hello!"
        }
        ],
        temperature=0,
        n=5,
        extra_body={
            "use_beam_search":True
        }
    )
    assert completion.id != None
    assert len(completion.choices) == 5

@allure.title("对话_设置max_completion_tokens时，使用束搜索")       
def test_with_beam_search_with_max_tokens():
    completion = client.chat.completions.create(
        model=model,
        messages=[
        {
            "role": "developer",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "Hello!"
        }
        ],
        temperature=0,
        n=5,
        max_completion_tokens=26,
        extra_body={
            "use_beam_search":True
        }
    )
    print(completion.choices)
    assert completion.id != None
    assert len(completion.choices) == 5
    content_0 = completion.choices[0].message.content
    content_1 = completion.choices[1].message.content
    content_2 = completion.choices[2].message.content
    content_3 = completion.choices[3].message.content
    content_4 = completion.choices[4].message.content
    # assert content_0 != content_1 != content_2 != content_3 != content_4 
