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
