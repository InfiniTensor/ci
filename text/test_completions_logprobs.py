import os
from openai import OpenAI,BadRequestError
import pytest
from openai.types import Completion,CompletionChoice
from openai import Stream,AsyncStream
import openai
import allure
from debugtalk import *

@pytest.mark.asyncio
@allure.title("文本补全_logprobs为True，返回结果包含logprobs信息")        
async def test_logprobs_true(client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt="Hello! Where is Beijing",
        temperature=0,
        logprobs=True,
        max_tokens=20
    )
    print(completion)
    assert isinstance(completion, Completion) == True
    assert hasattr(completion.choices[0],"logprobs")
    assert hasattr(completion.choices[0].logprobs,"top_logprobs") 
    
    logprobs_tokens=""
    for item in completion.choices[0].logprobs.top_logprobs:
        logprobs_tokens += list(item.keys())[0]
        assert list(item.values())[0] == 0.0
    print(logprobs_tokens)
    assert logprobs_tokens == completion.choices[0].text

@pytest.mark.asyncio
@allure.title("文本补全_logprobs为1，温度为0.6，返回结果包含logprobs信息，token预测概率基本不为1")        
async def test_logprobs_1_6(client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt="Hello! Where is Beijing",
        temperature=0.6,
        logprobs=1,
        max_tokens=20
    )
    print(completion)
    assert isinstance(completion, Completion) == True
    assert hasattr(completion.choices[0],"logprobs")
    assert hasattr(completion.choices[0].logprobs,"top_logprobs") 
    
    logprobs_tokens=""
    token_1=0
    for item in completion.choices[0].logprobs.top_logprobs:
        logprobs_tokens += list(item.keys())[0]
        if list(item.values())[0] == 0.0:
            token_1 += 1
    assert token_1 < len(completion.choices[0].logprobs.top_logprobs)
    print(logprobs_tokens)
    assert logprobs_tokens == completion.choices[0].text

@pytest.mark.asyncio
@allure.title("文本补全_logprobs为null，不加top_logprobs字段时，返回结果logprobs信息为None")        
async def test_logprobs_null(client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt="Hello! Where is Beijing",
        temperature=0,
        logprobs=None,
        max_tokens=20
    )
    print(completion)
    assert isinstance(completion, Completion) == True
    assert completion.choices[0].logprobs == None

@pytest.mark.asyncio    
@allure.title("文本补全_logprobs为0（integer or null），返回400")        
async def test_logprobs_0(client):
    try:
        await client.completions.create(
            model=os_env('MODEL'),
            prompt="Hello! Where is Beijing",
            temperature=0,
            logprobs=0,
            max_tokens=20
            
        )
    except BadRequestError as e:
        assert "Did not output logprobs" in e.message

    
@pytest.mark.asyncio    
@allure.title("文本补全_logprobs为False（integer or null），返回400")        
async def test_logprobs_false(client):
    try:
        await client.completions.create(
            model=os_env('MODEL'),
            prompt="Hello! Where is Beijing",
            temperature=0,
            logprobs=False,
            max_tokens=20
            
        )
    except BadRequestError as e:
        assert "Did not output logprobs" in e.message

@pytest.mark.asyncio
@allure.title("文本补全_logprobs为1临界值时，返回结果包含logprobs信息,每个top_logprobs包含1个预测token")        
async def test_logprobs_1(client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt="Hello! Where is Beijing",
        temperature=0,
        logprobs=1,
        max_tokens=20
    )
    print(completion)
    assert isinstance(completion, Completion) == True
    assert hasattr(completion.choices[0],"logprobs")
    assert hasattr(completion.choices[0].logprobs,"top_logprobs") 
    
    logprobs_tokens=""
    for item in completion.choices[0].logprobs.top_logprobs:
        assert len(item) == 1
        logprobs_tokens += list(item.keys())[0]
        assert list(item.values())[0] == 0.0
    print(logprobs_tokens)
    assert logprobs_tokens == completion.choices[0].text

@pytest.mark.asyncio
@allure.title("文本补全_logprobs为1临界值时，echo为true，返回结果包含logprobs信息,每个top_logprobs包含1个预测token")        
async def test_logprobs_echo_1(client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt="Hello! Where is Beijing",
        temperature=0,
        logprobs=1,
        max_tokens=20,
        echo=True
    )
    print(completion)
    assert isinstance(completion, Completion) == True
    assert hasattr(completion.choices[0],"logprobs")
    assert hasattr(completion.choices[0].logprobs,"top_logprobs") 
    
    logprobs_tokens=""
    for item in completion.choices[0].logprobs.top_logprobs:
        
        if item !=None:
            assert len(item) == 1
            logprobs_tokens += list(item.keys())[0]
            assert list(item.values())[0] == 0.0
    print(logprobs_tokens)
    assert logprobs_tokens == completion.choices[0].text

@pytest.mark.asyncio
@allure.title("文本补全_logprobs为2，返回结果包含logprobs信息,每个top_logprobs包含2个预测token")        
async def test_logprobs_2(client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt="Hello! Where is Beijing",
        temperature=0,
        logprobs=2,
        max_tokens=20
    )
    assert isinstance(completion, Completion) == True
    assert hasattr(completion.choices[0],"logprobs")
    assert hasattr(completion.choices[0].logprobs,"top_logprobs") 
    logprobs_tokens=""
    for item in completion.choices[0].logprobs.top_logprobs:
        assert len(item) == 2
        logprobs_tokens += list(item.keys())[0]
    assert logprobs_tokens == completion.choices[0].text

@pytest.mark.asyncio
@allure.title("文本补全_logprobs为临界值5时，返回结果包含logprobs信息，每个top_logprobs包含5个预测token")        
async def test_logprobs_5(client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt="Hello! Where is Beijing",
        temperature=0,
        logprobs=5,
        max_tokens=20
    )
    assert isinstance(completion, Completion) == True
    assert hasattr(completion.choices[0],"logprobs")
    assert hasattr(completion.choices[0].logprobs,"top_logprobs") 
    logprobs_tokens=""
    for item in completion.choices[0].logprobs.top_logprobs:
        assert len(item) == 5
        logprobs_tokens += list(item.keys())[0]
    assert logprobs_tokens == completion.choices[0].text

@pytest.mark.asyncio    
@allure.title("文本补全_logprobs为无效值6时，返回400")        
async def test_logprobs_6(client):
    try:
        await client.completions.create(
            model=os_env('MODEL'),
            prompt="Hello! Where is Beijing",
            temperature=0,
            logprobs=6,
            max_tokens=20
            
        )
    except BadRequestError as e:
        assert "Did not output logprobs" in e.message





@pytest.mark.asyncio
@allure.title("文本补全_stream模式下logprobs为True，返回结果包含logprobs信息")        
async def test_logprobs_stream_true(client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt="Hello! Where is Beijing",
        temperature=0,
        logprobs=True,
        max_tokens=20,
        stream=True
    )
    assert isinstance(completion, AsyncStream) == True
    async for chunk in completion:
        item = chunk.choices[0]
        assert hasattr(item,"logprobs")
        assert hasattr(item.logprobs,"top_logprobs")
        assert len(item.logprobs.top_logprobs) == 1
        assert item.logprobs.token_logprobs[0]==0.0

@pytest.mark.asyncio
@allure.title("文本补全_stream模式下logprobs为1，温度为0.6，返回结果包含logprobs信息，token预测概率基本不为1")        
async def test_logprobs_stream_1_6(client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt="Hello! Where is Beijing",
        temperature=0.6,
        logprobs=1,
        max_tokens=20,
        stream=True
    )
    assert isinstance(completion, AsyncStream) == True
    logprobs_1=0
    chunk_len=0
    async for chunk in completion:
        chunk_len += 1
        item = chunk.choices[0]
        assert hasattr(item,"logprobs")
        assert hasattr(item.logprobs,"top_logprobs")
        assert len(item.logprobs.top_logprobs) == 1
        if item.logprobs.token_logprobs[0] ==0.0:
            logprobs_1 += 1
    assert logprobs_1 < chunk_len

@pytest.mark.asyncio
@allure.title("文本补全_stream模式下logprobs为null，不加top_logprobs字段时，返回结果logprobs信息为None")        
async def test_logprobs_stream_null(client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt="Hello! Where is Beijing",
        temperature=0,
        logprobs=None,
        max_tokens=20,
        stream=True
    )
    assert isinstance(completion, AsyncStream) == True
    async for chunk in completion:
        assert chunk.choices[0].logprobs == None
       

@pytest.mark.asyncio    
@allure.title("文本补全_stream模式下logprobs为0（integer or null），返回400")        
async def test_logprobs_stream_0(client):
    try:
        await client.completions.create(
            model=os_env('MODEL'),
            prompt="Hello! Where is Beijing",
            temperature=0,
            logprobs=0,
            max_tokens=20,
            stream=True
        )
    except BadRequestError as e:
        assert "Did not output logprobs" in e.message

    
@pytest.mark.asyncio    
@allure.title("文本补全_stream模式下logprobs为False（integer or null），返回400")        
async def test_logprobs_stream_false(client):
    try:
        await client.completions.create(
            model=os_env('MODEL'),
            prompt="Hello! Where is Beijing",
            temperature=0,
            logprobs=False,
            max_tokens=20
            
        )
    except BadRequestError as e:
        assert "Did not output logprobs" in e.message

@pytest.mark.asyncio
@allure.title("文本补全_stream模式下logprobs为1临界值时，返回结果包含logprobs信息,每个top_logprobs包含1个预测token")        
async def test_logprobs_stream_1(client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt="Hello! Where is Beijing",
        temperature=0,
        logprobs=1,
        max_tokens=20,
        stream=True
    )
    assert isinstance(completion, AsyncStream) == True
    async for chunk in completion:
        item = chunk.choices[0]
        assert hasattr(item,"logprobs")
        assert hasattr(item.logprobs,"top_logprobs")
        assert len(item.logprobs.top_logprobs[0]) == 1
        

@pytest.mark.asyncio
@allure.title("文本补全_stream模式下logprobs为1临界值时，echo为true，返回结果包含logprobs信息,每个top_logprobs包含1个预测token")        
async def test_logprobs_stream_echo_1(client):
    prompt="Hello! Where is Beijing"
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt=prompt,
        temperature=0,
        logprobs=1,
        max_tokens=20,
        echo=True,
        stream=True
    )
    assert isinstance(completion, AsyncStream) == True
    async for chunk in completion:
        item = chunk.choices[0]
        assert hasattr(item,"logprobs")
        assert hasattr(item.logprobs,"top_logprobs")
        if len(item.logprobs.tokens) > 1:
            assert ''.join(item.logprobs.tokens[:-1]) == prompt
        elif len(item.logprobs.tokens) == 1:
            assert len(item.logprobs.top_logprobs) == 1

@pytest.mark.asyncio
@allure.title("文本补全_stream模式下logprobs为2，返回结果包含logprobs信息,每个top_logprobs包含2个预测token")        
async def test_logprobs_stream_2(client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt="Hello! Where is Beijing",
        temperature=0,
        logprobs=2,
        max_tokens=20,
        stream=True
    )
    assert isinstance(completion, AsyncStream) == True
    async for chunk in completion:
        item = chunk.choices[0]
        assert hasattr(item,"logprobs")
        assert hasattr(item.logprobs,"top_logprobs")
        assert len(item.logprobs.top_logprobs[0]) == 2

@pytest.mark.asyncio
@allure.title("文本补全_stream模式下logprobs为临界值5时，返回结果包含logprobs信息，每个top_logprobs包含5个预测token")        
async def test_logprobs_stream_5(client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt="Hello! Where is Beijing",
        temperature=0,
        logprobs=5,
        max_tokens=20,
        stream=True
    )
    assert isinstance(completion, AsyncStream) == True
    async for chunk in completion:
        item = chunk.choices[0]
        assert hasattr(item,"logprobs")
        assert hasattr(item.logprobs,"top_logprobs")
        assert len(item.logprobs.top_logprobs[0]) == 5

@pytest.mark.asyncio    
@allure.title("文本补全_logprobs为无效值6时，返回400")        
async def test_logprobs_6(client):
    try:
        await client.completions.create(
            model=os_env('MODEL'),
            prompt="Hello! Where is Beijing",
            temperature=0,
            logprobs=6,
            max_tokens=20
            
        )
    except BadRequestError as e:
        assert "Did not output logprobs" in e.message
        
