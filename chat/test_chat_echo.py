from typing import NamedTuple
import pytest
import openai
from openai import OpenAI
import allure

class TestCase(NamedTuple):
    echo: bool
    
client = OpenAI(
    # This is the default and can be omitted
    api_key="-",
    base_url="http://10.208.130.44:2025/v1"
)

model = "deepseek"

@pytest.mark.asyncio
@pytest.mark.parametrize(
    "test_case",
    [
        TestCase( echo=True),
        TestCase( echo=False)
    ],
)
@allure.title("对话_使用参数化判断echo为true/false时返回的信息正确") 
def test_chat_with_echo(test_case: TestCase):
    saying: str = "Here is a common saying about apple. An apple a day, keeps"
    # test echo with continue_final_message parameter
    chat_completion = client.chat.completions.create(
        model=model,
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