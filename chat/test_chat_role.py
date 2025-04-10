import os
from openai import OpenAI,AsyncOpenAI
import pytest
from openai.types.chat import ChatCompletionChunk,ChatCompletion
from openai import Stream
import openai
import allure
import asyncio
import ast
from debugtalk import *

@pytest.mark.asyncio
@allure.title("对话_判断role为user、developer...等允许的角色时，返回结果正确")
async def test_support_role(client):
    # 判断stream为false时，返回为ChatCompletion类型
    developer_completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
        {
            "role": "developer",
            "content": "what is 1+1? please provide the result without any other text."
        }
        ],
        temperature=0,
        stream=False,
    )
    assert isinstance(developer_completion, ChatCompletion) == True
    assert developer_completion.choices[0].message.role == 'assistant'
    res_developer = developer_completion.choices[0].message.content
    user_completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
        {
            "role": "user",
            "content": "what is 1+1? please provide the result without any other text."
        }
        ],
        temperature=0,
        stream=False,
    )
    assert isinstance(user_completion, ChatCompletion) == True
    assert user_completion.choices[0].message.role == 'assistant'
    res_user = user_completion.choices[0].message.content
    system_completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
        {
            "role": "system",
            "content": "what is 1+1? please provide the result without any other text."
        }
        ],
        temperature=0,
        stream=False,
    )
    assert isinstance(system_completion, ChatCompletion) == True
    assert system_completion.choices[0].message.role == 'assistant'
    res_system = system_completion.choices[0].message.content
    assistant_completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
        {
            "role": "assistant",
            "content": "what is 1+1? please provide the result without any other text."
        }
        ],
        temperature=0,
        stream=False,
    )
    assert isinstance(assistant_completion, ChatCompletion) == True
    assert assistant_completion.choices[0].message.role == 'assistant'
    res_assistant = assistant_completion.choices[0].message.content
    assert res_developer != res_user != res_assistant
    assert res_developer != res_system

@pytest.mark.asyncio
@allure.title("对话_判断role为自定义角色时，返回结果错误")
async def test_custom_role(client):
    # Not sure how the model handles custom roles so we just check that
    # both string and complex message content are handled in the same way
    try:
        await client.chat.completions.create(
            model=os_env('MODEL'),
            messages=[{
                "role": "my-custom-role",
                "content": "what is 1+1?",
            }],  # type: ignore
            temperature=0,
            )

    except openai.BadRequestError as e:
        assert e.status_code == 400
        assert "('body', 'messages', 0, 'typed-dict', 'role')" in e.response.json()['message']