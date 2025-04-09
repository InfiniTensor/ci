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

@allure.title("对话_判断设置stop字符时，输出遇到stop字符停止输出")        
def test_not_stream_with_stop(test_not_stream_chat):
    stop_world = "can"
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
        stop=[stop_world],
    )
    assert isinstance(completion, ChatCompletion) == True
    assert test_not_stream_chat[0] != completion.choices[0].message.content
    assert test_not_stream_chat[1] > completion.usage.completion_tokens
    text = stop_text(test_not_stream_chat[0],stop_world)
    assert completion.choices[0].message.content == text