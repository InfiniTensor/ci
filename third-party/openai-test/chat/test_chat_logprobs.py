import os
from openai import OpenAI,BadRequestError
import pytest
from openai.types.chat import ChatCompletionChunk,ChatCompletion,ChatCompletionTokenLogprob
from openai import Stream,AsyncStream
import openai
import allure
from debugtalk import *

pytestmark = pytest.mark.skip(reason="临时禁用 logprobs 测试")

@pytest.mark.asyncio
@allure.title("对话_logprobs为True，不加top_logprobs字段时，返回结果正确没有logprobs信息")        
async def test_logprobs_true(client):
    completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
        {
            "role": "developer",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "Hello! Where is Beijing"
        }
        ],
        temperature=0,
        logprobs=True,
        max_completion_tokens=20
    )
    assert isinstance(completion, ChatCompletion) == True
    assert completion.choices[0].logprobs != None
    logprobs_tokens=""
    for item in completion.choices[0].logprobs.content:
        assert isinstance(item,ChatCompletionTokenLogprob) == True
        logprobs_tokens += item.token
    print(completion)

    
@pytest.mark.asyncio    
@allure.title("对话_logprobs为False，不加top_logprobs字段时，返回结果正确")        
async def test_logprobs_false(client):
    completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
        {
            "role": "developer",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "Hello! Where is Beijing"
        }
        ],
        temperature=0,
        logprobs=False,
        max_completion_tokens=20
        
    )
    print(completion)
    assert isinstance(completion, ChatCompletion) == True
    assert completion.choices[0].logprobs ==None

@pytest.mark.asyncio
@allure.title("对话_logprobs为True，top_logprobs=0超范围时，返回400,提示信息正确结果正确")        
async def test_logprobs_true_0(client):
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
            logprobs=True,
            top_logprobs=0, 
        )
    except BadRequestError as e:
        assert 'Did not output logprobs' in e.message
        
@pytest.mark.asyncio
@allure.title("对话_logprobs为True，top_logprobs=17超范围时，返回400,提示信息正确结果正确")        
async def test_logprobs_true_17(client):
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
            logprobs=True,
            top_logprobs=17
        )
    except BadRequestError as e:
        assert 'logprobs is larger than max_best_of (default as 16).' in e.message

@pytest.mark.asyncio
@allure.title("对话_logprobs为True，top_logprobs=16临界时，推理正确包含logprobs信息")        
async def test_logprobs_true_16(client):
    completion =  await client.chat.completions.create(
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
        logprobs=True,
        top_logprobs=16,
        max_completion_tokens=20
    )
    assert isinstance(completion, ChatCompletion) == True
    assert completion.choices[0].logprobs != None
    logprobs_tokens=""
    print(completion)
    for item in completion.choices[0].logprobs.content:
        assert isinstance(item,ChatCompletionTokenLogprob) == True
        logprobs_tokens += item.token
        assert len(item.top_logprobs) == 16
    print(logprobs_tokens)
    
    
@pytest.mark.asyncio
@allure.title("对话_logprobs为True，top_logprobs=8范围内值时，推理正确包含logprobs信息")        
async def test_logprobs_true_8(client):
    completion =  await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
        {
            "role": "developer",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "Hello! Where is BeiJing?"
        }
        ],
        temperature=0,
        logprobs=True,
        top_logprobs=8,
        max_completion_tokens=20
    )
    assert isinstance(completion, ChatCompletion) == True
    assert completion.choices[0].logprobs != None
    logprobs_tokens=""
    print(completion)
    for item in completion.choices[0].logprobs.content:
        assert isinstance(item,ChatCompletionTokenLogprob) == True
        logprobs_tokens += item.token
        assert len(item.top_logprobs) == 8
    print(logprobs_tokens)

@pytest.mark.asyncio
@allure.title("对话_logprobs为True，echo为True,top_logprobs=8范围内值时，推理正确包含logprobs信息")        
async def test_logprobs_echo_true_8(client):
    completion =  await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
        {
            "role": "developer",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "Hello! Where is BeiJing?"
        }
        ],
        temperature=0,
        logprobs=True,
        top_logprobs=8,
        max_completion_tokens=20,
        extra_body={
            "echo": True,
        }
    )
    assert isinstance(completion, ChatCompletion) == True
    assert completion.choices[0].logprobs != None
    logprobs_tokens=""
    # print(completion)
    print(completion.choices[0].message.content)
    for item in completion.choices[0].logprobs.content:
        # print(item)
        assert isinstance(item,ChatCompletionTokenLogprob) == True
        logprobs_tokens += item.token
        assert len(item.top_logprobs) == 8
    assert "Hello! Where is BeiJing?" in logprobs_tokens
    
@pytest.mark.asyncio
@allure.title("对话_logprobs为True，top_logprobs=None时，推理正确没有logprobs信息")        
async def test_logprobs_true_none(client):
    completion =  await client.chat.completions.create(
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
        logprobs=True,
        top_logprobs=None,
        max_completion_tokens=20
    )
    assert isinstance(completion, ChatCompletion) == True
    assert completion.choices[0].logprobs == None
    
@pytest.mark.asyncio
@allure.title("对话_logprobs为False，top_logprobs=8范围内值时，推理没有logprobs信息")        
async def test_logprobs_false_8(client):
    completion =  await client.chat.completions.create(
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
        logprobs=False,
        top_logprobs=8,
        max_completion_tokens=20
        
    )
    assert isinstance(completion, ChatCompletion) == True
    assert "logprobs" not in completion.choices[0]
    



# jjjjjjjjjjjjjjjjjjjjjjjjjjjjjj
@pytest.mark.asyncio
@allure.title("对话_stream模式，logprobs为True，不加top_logprobs字段时，返回结果正确没有logprobs信息")        
async def test_stream_logprobs_true(client):
    completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
        {
            "role": "developer",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "Hello! Where is Beijing"
        }
        ],
        temperature=0,
        stream=True,
        logprobs=True,
        max_completion_tokens=20
    )
    assert isinstance(completion, AsyncStream) == True
    chunks=[]
    logprobs_tokens=[]
    index=0
    async for chunk in completion:
        assert isinstance(chunk, ChatCompletionChunk) == True
        delta = chunk.choices[0].delta
        logprobs = chunk.choices[0].logprobs
        
        if delta.role:
            assert index == 0
            assert delta.role == "assistant"
            assert delta.content == ""
        else:
            print('~'*50)
            print(logprobs)
            assert len(logprobs.content) == 1
            assert len(logprobs.content[0].top_logprobs) == 0
        if delta.content:
            chunks.append(delta.content)
            logprobs_tokens.append(logprobs.content[0].token)
        index += 1
    content = "".join(chunks)
    logprobs = "".join(logprobs_tokens)
    print(content)
    print(logprobs)
    

    
@pytest.mark.asyncio    
@allure.title("对话_stream模式，logprobs为False，不加top_logprobs字段时，返回结果正确没有logprobs信息")        
async def test_stream_logprobs_false(client):
    completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
        {
            "role": "developer",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "Hello! Where is Beijing"
        }
        ],
        temperature=0,
        stream=True,
        logprobs=False,
        max_completion_tokens=20
        
        
    )
    assert isinstance(completion, AsyncStream) == True
    async for chunk in completion:
        assert isinstance(chunk, ChatCompletionChunk) == True
        delta = chunk.choices[0].delta
        
        assert "logprobs" not in chunk.choices[0]



@pytest.mark.asyncio
@allure.title("对话_stream模式，logprobs为True，top_logprobs=0超范围时，返回400,提示信息正确结果正确")        
async def test_stram_logprobs_true_0(client):
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
            stream=True,
            logprobs=True,
            top_logprobs=0
        )
    except BadRequestError as e:
        assert 'Did not output logprobs' in e.message
        
@pytest.mark.asyncio
@allure.title("对话_stream模式，logprobs为True，top_logprobs=17超范围时，返回400,提示信息正确结果正确")        
async def test_stream_logprobs_true_17(client):
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
            stream=True,
            logprobs=True,
            top_logprobs=17
        )
    except BadRequestError as e:
        assert 'logprobs is larger than max_best_of (default as 16).' in e.message

@pytest.mark.asyncio
@allure.title("对话_stream模式，logprobs为True，top_logprobs=16临界时，推理正确包含logprobs信息")        
async def test_stream_logprobs_true_16(client):
    completion =  await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
        {
            "role": "developer",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "Hello! Where is BeiJing?"
        }
        ],
        temperature=0,
        stream=True,
        logprobs=True,
        top_logprobs=16,
        max_completion_tokens=20
    )
    assert isinstance(completion, AsyncStream) == True
    async for chunk in completion:
        assert isinstance(chunk, ChatCompletionChunk) == True
        delta = chunk.choices[0].delta
        if delta.role:
            assert delta.role == "assistant"
            assert delta.content == ""
        else:
            top_logprobs = chunk.choices[0].logprobs.content[0].top_logprobs
            print(len(top_logprobs))
            assert len(top_logprobs) == 16


    
@pytest.mark.asyncio
@allure.title("对话_stream模式，logprobs为True，top_logprobs=8范围内值时，推理正确包含logprobs信息")        
async def test_stream_logprobs_true_8(client):
    completion =  await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
        {
            "role": "developer",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "Hello! Where is BeiJing?"
        }
        ],
        temperature=0,
        logprobs=True,
        stream=True,
        top_logprobs=8,
        max_completion_tokens=20
        
    )
    assert isinstance(completion, AsyncStream) == True
    async for chunk in completion:
        assert isinstance(chunk, ChatCompletionChunk) == True
        delta = chunk.choices[0].delta
        if delta.role:
            assert delta.role == "assistant"
            assert delta.content == ""
        else:
            top_logprobs = chunk.choices[0].logprobs.content[0].top_logprobs
            print(len(top_logprobs))
            assert len(top_logprobs) == 8
    
@pytest.mark.asyncio
@allure.title("对话_stream模式，top_logprobs=None时，推理正确没有logprobs信息")        
async def test_stream_logprobs_true_none(client):
    completion =  await client.chat.completions.create(
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
        logprobs=True,
        stream=True,
        top_logprobs=None,
        max_completion_tokens=20
        
    )
    assert isinstance(completion, AsyncStream) == True
    async for chunk in completion:
        assert isinstance(chunk, ChatCompletionChunk) == True
        delta = chunk.choices[0].delta
        if delta.role:
            assert delta.role == "assistant"
            assert delta.content == ""
        else:
            top_logprobs = chunk.choices[0].logprobs
            print(top_logprobs)
            assert "logprobs" not in chunk.choices[0]
    
@pytest.mark.asyncio
@allure.title("对话_stream模式，logprobs为False，top_logprobs=8范围内值时，推理没有logprobs信息")        
async def test_stream_logprobs_false_8(client):
    completion =  await client.chat.completions.create(
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
        logprobs=False,
        stream=True,
        top_logprobs=8,
        max_completion_tokens=20
        
    )
    assert isinstance(completion, AsyncStream) == True
    async for chunk in completion:
        assert isinstance(chunk, ChatCompletionChunk) == True
        delta = chunk.choices[0].delta
        if delta.role:
            assert delta.role == "assistant"
            assert delta.content == ""
        else:
            top_logprobs = chunk.choices[0].logprobs
            print(top_logprobs)
            assert "logprobs" not in chunk.choices[0]
            
# 添加温度不同概率的用例
# 添加echo的用例