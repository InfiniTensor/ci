import os
from openai import OpenAI
import pytest
import allure
from openai import BadRequestError
from debugtalk import *
import openai

@pytest.mark.skip("待完成")
@pytest.mark.asyncio
@allure.title("文本补全_长上下文推理测试")
async def test_long_context(client):
    # max_length=get_max_len('/home/weight/Qwen3/Qwen/Qwen3-32B')
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt="How do I check if a Python object is an instance of a class?",
        temperature=0,
        # max_tokens=max_length-100
    )
    print(completion)
    assert completion.object == 'text_completion'
    assert completion.id != None
    assert len(completion.choices) == 1