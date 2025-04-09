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
    print(completion)
    assert completion.object == 'chat.completion'
    assert isinstance(completion, ChatCompletion) == True
    assert completion.choices[0].message.role == 'assistant'
    no_stop_content = completion.choices[0].message.content
    no_stop_tokens = completion.usage.completion_tokens
    print(no_stop_content)
    return no_stop_content,no_stop_tokens

@allure.title("对话_判断stream为true时，返回为流式Stream类型")    
def test_stream_chat(test_not_stream_chat):
    # 判断stream为true时，返回为流式Stream类型
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
        stream=True,
    )
    chunks= []
    assert isinstance(completion, Stream) == True
    for chunk in completion:
        assert isinstance(chunk, ChatCompletionChunk) == True
        delta = chunk.choices[0].delta
        if delta.role:
            assert delta.role == "assistant"
        if delta.content:
            chunks.append(delta.content)
    content = "".join(chunks)
    assert content == test_not_stream_chat[0]

@allure.title("对话_判断stream为true时，stream_options两个选项全为true时，所有chunk的usage不为None")         
def test_stream_with_options_all_true():
    # 判断stream为true时，stream_options两个选项全为true
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
        stream=True,
        stream_options={
            "include_usage":True,
            "continuous_usage_stats":True
        },
        max_completion_tokens=16
    )
    assert isinstance(completion, Stream) == True
    last_completion_tokens = 0
    for chunk in completion:
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
    assert last_completion_tokens == 16  
           
@allure.title("对话_判断stream为true，include_usage为true时，最后的usage不为None")
def test_stream_with_option_include_usage_true():
    # 判断stream为true时，include_usage为true
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
        stream=True,
        stream_options={
            "include_usage":True,
            "continuous_usage_stats":False
        }
    )
    assert isinstance(completion, Stream) == True
    for chunk in completion:
        assert isinstance(chunk, ChatCompletionChunk) == True
        if chunk.choices[0].finish_reason is None:
            assert chunk.usage is None
        else:
            assert chunk.usage is None
            final_chunk =  completion.__next__()
            assert final_chunk.usage is not None
            assert final_chunk.usage.prompt_tokens > 0
            assert final_chunk.usage.completion_tokens > 0
            assert final_chunk.usage.total_tokens == (
                final_chunk.usage.prompt_tokens +
                final_chunk.usage.completion_tokens)
            assert final_chunk.choices == []
        
@allure.title("对话_判断stream为true，continuous_usage_stats为true时，所有的usage不为None")            
def test_stream_with_option_continuous_usage_stats_true():
    # 判断stream为true时，continuous_usage_stats为true
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
        stream=True,
        stream_options={
            "continuous_usage_stats":True
        }
    )
    assert isinstance(completion, Stream) == True
    for chunk in completion:
        assert isinstance(chunk, ChatCompletionChunk) == True
        assert chunk.usage != None
        
@allure.title("对话_判断stream为false时，传入stream_options，服务报400，提示信息正确")            
def test_not_stream_with_option_continuous_usage_stats_true():
    # 判断stream为true时，continuous_usage_stats为true
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
            stream=False,
            stream_options={
                "continuous_usage_stats":True
            }
    )
    except openai.BadRequestError as e:
        assert e.status_code == 400
        assert 'Stream options can only be defined when `stream=True`.' in e.message

    