import os
from openai import OpenAI
import pytest
from openai.types.chat import ChatCompletionChunk,ChatCompletion
from openai import AsyncStream
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
    assert completion.object == 'chat.completion'
    assert isinstance(completion, ChatCompletion) == True
    assert completion.choices[0].message.role == 'assistant'

@pytest.mark.asyncio
@allure.title("对话_判断stream为true时，返回为流式AsyncStream类型")    
async def test_stream_chat(client):
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
    # 判断stream为true时，返回为流式AsyncStream类型
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
        stream=True,
    )
    chunks= []
    index=0
    assert isinstance(completion_1, AsyncStream) == True
    async for chunk in completion_1:
        assert isinstance(chunk, ChatCompletionChunk) == True
        delta = chunk.choices[0].delta
        if delta.role:
            assert index == 0
            assert delta.role == "assistant"
            assert delta.content == ""
        if delta.content:
            chunks.append(delta.content)
        index += 1
    content = "".join(chunks)
    assert content == completion_0.choices[0].message.content

@pytest.mark.asyncio
@allure.title("对话_判断stream为true时，stream_options两个选项全为true时，所有chunk的usage不为None")         
async def test_stream_with_options_all_true(client):
    max_tokens = 16
    # 判断stream为true时，stream_options两个选项全为true
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
        stream=True,
        stream_options={
            "include_usage":True,
            "continuous_usage_stats":True
        },
        max_completion_tokens=max_tokens
    )
    assert isinstance(completion, AsyncStream) == True
    last_completion_tokens = 0
    async for chunk in completion:
        assert isinstance(chunk, ChatCompletionChunk) == True
        assert chunk.usage != None
        assert chunk.usage.prompt_tokens >= 0
        assert last_completion_tokens == 0 or \
               chunk.usage.completion_tokens > last_completion_tokens or \
               (
                   not chunk.choices and
                   chunk.usage.completion_tokens == last_completion_tokens
               )
        assert chunk.usage.total_tokens == (chunk.usage.prompt_tokens +
                                            chunk.usage.completion_tokens)
        last_completion_tokens = chunk.usage.completion_tokens
    assert last_completion_tokens <= max_tokens

@pytest.mark.asyncio           
@allure.title("对话_判断stream为true，include_usage为true时，最后的usage不为None")
async def test_stream_with_option_include_usage_true(client):
    # 判断stream为true时，include_usage为true
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
        stream=True,
        stream_options={
            "include_usage":True,
            "continuous_usage_stats":False
        }
    )
    assert isinstance(completion, AsyncStream) == True
    async for chunk in completion:
        assert isinstance(chunk, ChatCompletionChunk) == True
        if chunk.choices[0].finish_reason is None:
            assert chunk.usage is None
        else:
            assert chunk.usage is None
            final_chunk = await completion.__anext__()
            assert final_chunk.usage is not None
            assert final_chunk.usage.prompt_tokens > 0
            assert final_chunk.usage.completion_tokens > 0
            assert final_chunk.usage.total_tokens == (
                final_chunk.usage.prompt_tokens +
                final_chunk.usage.completion_tokens)
            assert final_chunk.choices == []

@pytest.mark.asyncio        
@allure.title("对话_判断stream为true，continuous_usage_stats为true时，所有的usage不为None")            
async def test_stream_with_option_continuous_usage_stats_true(client):
    # 判断stream为true时，continuous_usage_stats为true
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
        stream=True,
        stream_options={
            "continuous_usage_stats":True
        }
    )
    assert isinstance(completion, AsyncStream) == True
    async for chunk in completion:
        assert isinstance(chunk, ChatCompletionChunk) == True
        assert chunk.usage != None

@pytest.mark.asyncio        
@allure.title("对话_判断stream为false时，传入stream_options，服务报400，提示信息正确")    
        
async def test_not_stream_with_option_continuous_usage_stats_true(client):
    # 判断stream为true时，continuous_usage_stats为true
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
            stream=False,
            stream_options={
                "continuous_usage_stats":True
            }
    )
    except openai.BadRequestError as e:
        assert e.status_code == 400
        assert 'Stream options can only be defined when `stream=True`.' in e.message

    
