from typing import NamedTuple
import pytest
import openai
from openai import OpenAI
import allure
from debugtalk import *

class TestEcho(NamedTuple):
    echo: bool

@pytest.mark.asyncio
@pytest.mark.parametrize(
    "test_case",
    [
        TestEcho( echo=True),
        TestEcho( echo=False)
    ],
)
@allure.title("对话_使用参数化判断echo为{test_case.echo}时返回的信息正确") 
async def test_chat_with_echo(test_case: TestEcho, client):
    saying: str = "Here is a common saying about apple. An apple a day, keeps"
    # test echo with continue_final_message parameter
    chat_completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[{
            "role": "user",
            "content": "tell me a common saying"
        }, {
            "role": "assistant",
            "content": saying
        }],
        extra_body={
            "echo": test_case.echo,

        })
    assert chat_completion.id is not None
    assert len(chat_completion.choices) == 1

    choice = chat_completion.choices[0]
    assert choice.finish_reason == "stop"

    message = choice.message
    if test_case.echo:
        assert message.content is not None and saying in message.content
    else:
        assert message.content is not None and saying not in message.content
    assert message.role == "assistant"