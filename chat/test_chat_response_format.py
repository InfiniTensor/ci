import os
from openai import OpenAI
import pytest
from openai.types.chat import ChatCompletionChunk,ChatCompletion
from openai import Stream
from pydantic import BaseModel
from enum import Enum
import json
import jsonschema
import ast
import allure
from debugtalk import *

def eval_correctness_json(expected, actual):
    # extract json string from string using regex
    import re
    actual = actual.replace('\n', '').replace(' ', '').strip()
    try:
        actual = re.search(r'\{.*\}', actual).group()
        actual = json.loads(actual)
    except Exception:
        return False

    return True

class CarType(str, Enum):
    sedan = "sedan test test test"
    suv = "SUV of mine"
    truck = "Truck or not"
    coupe = "Coupe is that so"


class CarDescription(BaseModel):
    brand: str
    model: str
    car_type: CarType

except_format = {
    "brand":'',
    "model":'',
    "car_type":''
}
json_schema = CarDescription.model_json_schema()


@pytest.mark.asyncio
@allure.title("对话_判断简单的对话结果返回内容类型为str")
async def test_normal_response(client):
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
    )
    assert isinstance(completion, ChatCompletion) == True
    assert eval_correctness_json(except_format,completion.choices[0].message.content) == False
    assert isinstance(completion.choices[0].message.content, str)

@pytest.mark.asyncio
@allure.title("对话_判断guided_json的对话结果返回内容类型为json且格式匹配提供的模板——1") 
async def test_response_format(client):
    # 判断stream为false时，返回为ChatCompletion类型
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
    assert isinstance(completion_0, ChatCompletion) == True
    result_0 = completion_0.choices[0].message.content
    
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
        extra_body={
        "guided_json": json_schema, 
        "guided_decoding_backend" : "xgrammar",
        "ignore_eos" : False, 
        "top_k" : 1},
    )
    assert isinstance(completion_1, ChatCompletion) == True
    result_1 = completion_1.choices[0].message.content
    assert result_0 != result_1
    eval_correctness_json(except_format,result_1)
    assert eval_correctness_json(except_format,result_1) == True

@pytest.mark.asyncio
@allure.title("对话_判断guided_json的对话结果返回内容类型为json且格式匹配提供的模板——2")     
async def test_guided_json_chat(sample_json_schema, client):
    messages = [
        {
        "role": "system",
        "content": "you are a helpful assistant"
        }, 
        {
        "role":"user",
        "content":
        f"Give an example JSON for an employee profile that "
        f"fits this schema: {sample_json_schema}"
        }
    ]
    chat_completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=messages,
        max_completion_tokens=1000,
        extra_body=dict(guided_json=sample_json_schema,
                        guided_decoding_backend='xgrammar'))
    message = chat_completion.choices[0].message
    assert message.content is not None
    json1 = json.loads(message.content)
    jsonschema.validate(instance=json1, schema=sample_json_schema)

    messages.append({"role": "assistant", "content": message.content})
    messages.append({
        "role":
        "user",
        "content":
        "Give me another one with a different name and age"
    })
    chat_completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=messages,
        max_completion_tokens=1000,
        extra_body=dict(guided_json=sample_json_schema,
                        guided_decoding_backend='xgrammar'))
    message = chat_completion.choices[0].message
    assert message.content is not None
    json2 = json.loads(message.content)
    jsonschema.validate(instance=json2, schema=sample_json_schema)
    assert json1["name"] != json2["name"]
    assert json1["age"] != json2["age"]