import os
from openai import OpenAI
import pytest
from openai.types.chat import ChatCompletionChunk,ChatCompletion
from openai import Stream
import openai
import allure
from debugtalk import *

@pytest.mark.asyncio
@allure.title("对话_判断stream为false时，返回为ChatCompletion类型")
async def test_not_stream_chat(client):
    # 判断stream为false时，返回为ChatCompletion类型
    completion = await client.chat.completions.create(
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
        stream=False,
    )
    assert isinstance(completion, ChatCompletion) == True
    assert completion.choices[0].message.role == 'assistant'


@pytest.mark.asyncio    
@allure.title("对话_判断设置max_tokens时，输出文本最长为max_tokens，stop reason为length")
async def test_not_stream_with_max_tokens(client):
    max_tokens = 6
    # 判断max_tokens参数生效
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
        stream=False,
    )
    content_0 = completion_0.choices[0].message.content
    tokens_0 = completion_0.usage.completion_tokens
    completion = await client.chat.completions.create(
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
        max_tokens=max_tokens
    )
    assert isinstance(completion, ChatCompletion) == True
    assert content_0 != completion.choices[0].message.content
    assert tokens_0 > completion.usage.completion_tokens
    assert completion.usage.completion_tokens == max_tokens
    assert completion.choices[0].finish_reason == 'length'
    
@pytest.mark.asyncio
@allure.title("对话_判断设置max_completion_tokens时，输出文本最长为max_completion_tokens，stop reason为length")
async def test_not_stream_with_max_completion_tokens(client):
    max_completion_tokens = 6
    # 判断max_tokens参数生效
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
        stream=False,
    )
    content_0 = completion_0.choices[0].message.content
    tokens_0 = completion_0.usage.completion_tokens
    completion = await client.chat.completions.create(
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
        max_completion_tokens=max_completion_tokens
    )
    assert isinstance(completion, ChatCompletion) == True
    assert content_0 != completion.choices[0].message.content
    assert tokens_0 > completion.usage.completion_tokens
    assert completion.usage.completion_tokens == max_completion_tokens
    assert completion.choices[0].finish_reason == 'length'

@pytest.mark.asyncio    
@allure.title("对话_判断设置max_completion_tokens != max_tokens时，400报错，返回正确提示信息")    
async def test_max_tokens_not_equal_max_completion_tokens(client):
    max_completion_tokens = 6
    # 判断max_tokens和max_completion_tokens不一致时提示信息正确
    try:
        await client.chat.completions.create(
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
            max_completion_tokens=max_completion_tokens,
            max_tokens=max_completion_tokens + 1
            
        )
    except openai.BadRequestError as e:
        assert e.status_code == 400
        assert 'max_tokens and max_completion_tokens cannot have different values.' in e.message

@pytest.mark.asyncio
@allure.title("对话_判断设置max_completion_tokens == max_tokens时，返回正确信息")    
async def test_max_tokens_equal_max_completion_tokens(client):
    max_completion_tokens = 6
    # 判断max_tokens和max_completion_tokens不一致时提示信息正确
    completion = await client.chat.completions.create(
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
        max_completion_tokens=max_completion_tokens,
        max_tokens=max_completion_tokens   
    )
    assert isinstance(completion, ChatCompletion) == True
    assert completion.usage.completion_tokens == max_completion_tokens
    assert completion.choices[0].finish_reason == 'length'


@pytest.mark.skip(reason='多进程暂不支持')
@pytest.mark.asyncio        
@allure.title("对话_不设置max_completion_tokens时，使用束搜索")   
async def test_with_beam_search_without_max_tokens(client):
    completion = await client.chat.completions.create(
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
        n=5,
        extra_body={
            "use_beam_search":True
        }
    )
    assert completion.id != None
    assert len(completion.choices) == 5

@pytest.mark.skip(reason='多进程暂不支持')
@pytest.mark.asyncio
@allure.title("对话_设置max_completion_tokens时，使用束搜索")       
async def test_with_beam_search_with_max_tokens(client):
    completion = await client.chat.completions.create(
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
        n=5,
        max_completion_tokens=26,
        extra_body={
            "use_beam_search":True
        }
    )
    assert completion.id != None
    assert len(completion.choices) == 5
    content_0 = completion.choices[0].message.content
    content_1 = completion.choices[1].message.content
    content_2 = completion.choices[2].message.content
    content_3 = completion.choices[3].message.content
    content_4 = completion.choices[4].message.content
    # assert content_0 != content_1 != content_2 != content_3 != content_4 
