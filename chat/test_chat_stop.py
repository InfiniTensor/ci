import os
from openai import OpenAI
import pytest
from openai.types.chat import ChatCompletionChunk,ChatCompletion
from openai import Stream
import openai
import allure
from debugtalk import *

@pytest.mark.asyncio
@allure.title("对话_判断设置stop字符时，输出遇到stop字符停止输出")        
async def test_not_stream_with_stop(client):
    completion_0 = await client.chat.completions.create(
        model=os_env('MODEL'),
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
    )
    content_0 = completion_0.choices[0].message.content
    tokens_0 = completion_0.usage.completion_tokens
    stop_world = get_stop_word(content_0)
    print('*'*50,stop_world)
    # 判断stream为false时，返回为ChatCompletion类型
    completion_1 = await client.chat.completions.create(
        model=os_env('MODEL'),
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
    assert isinstance(completion_1, ChatCompletion) == True
    assert content_0 != completion_1.choices[0].message.content
    assert tokens_0 > completion_1.usage.completion_tokens
    text = stop_text(content_0, stop_world)
    print('*'*50,completion_1.choices[0].message.content)
    print('*'*50,text)
    assert completion_1.choices[0].message.content == text