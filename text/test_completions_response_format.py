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
import openai
import re
import allure
from debugtalk import *

GUIDED_DECODING_BACKENDS = ["outlines", "lm-format-enforcer", "xgrammar"]
# 目前只支持 xgrammar
guided_decoding_backend = "xgrammar"
# @pytest.mark.parametrize("guided_decoding_backend", GUIDED_DECODING_BACKENDS)
@pytest.mark.asyncio
@allure.title("文本补全_判断使用guided_json时返回文本格式正确") 
async def test_guided_json_completion(sample_json_schema,client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt=f"Give an example JSON for an employee profile "
        f"that fits this schema: {sample_json_schema}",
        n=3,
        temperature=1.0,
        max_tokens=500,
        extra_body=dict(guided_json=sample_json_schema,
                        guided_decoding_backend=guided_decoding_backend))

    assert completion.id is not None
    assert len(completion.choices) == 3
    for i in range(3):
        output_json = json.loads(completion.choices[i].text)
        jsonschema.validate(instance=output_json, schema=sample_json_schema)
   
@pytest.mark.asyncio     
@allure.title("文本补全_判断目前不支持guided_regex") 
async def test_guided_regex_completion(sample_regex, client):
    try:
        await client.completions.create(
            model=os_env('MODEL'),
            prompt=f"Give an example IPv4 address with this regex: {sample_regex}",
            n=3,
            temperature=1.0,
            max_tokens=20,
            extra_body=dict(guided_regex=sample_regex,
                            guided_decoding_backend=guided_decoding_backend))
    except openai.BadRequestError as e:
        assert e.status_code == 400
        assert 'xgrammar only supports json or grammar guided decoding. Falling back to use outlines instead.' in e.message
    # assert completion.id is not None
    # assert len(completion.choices) == 3
    # for i in range(3):
    #     assert re.fullmatch(sample_regex,
    #                         completion.choices[i].text) is not None
@pytest.mark.asyncio
@allure.title("文本补全_判断目前不支持guided_choice") 
async def test_guided_choice_completion(sample_guided_choice, client):
    try:
        await client.completions.create(
            model=os_env('MODEL'),
            prompt="The best language for type-safe systems programming is ",
            n=2,
            temperature=1.0,
            max_tokens=10,
            extra_body=dict(guided_choice=sample_guided_choice,
                            guided_decoding_backend=guided_decoding_backend))
    except openai.BadRequestError as e:
        assert e.status_code == 400
        assert 'xgrammar only supports json or grammar guided decoding. Falling back to use outlines instead.' in e.message
    # assert completion.id is not None
    # assert len(completion.choices) == 2
    # for i in range(2):
    #     assert completion.choices[i].text in sample_guided_choice


@pytest.mark.asyncio
@allure.title("文本补全_判断使用guided_grammar时返回文本格式正确") 
async def test_guided_grammar(sample_sql_statements, client):
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt=("Generate a sql state that select col_1 from "
                "table_1 where it is equals to 1"),
        temperature=0.0,
        max_tokens=500,
        extra_body=dict(guided_grammar=sample_sql_statements))

    content = completion.choices[0].text

    # use Lark to parse the output, and make sure it's a valid parse tree
    from lark import Lark
    parser = Lark(sample_sql_statements)
    parser.parse(content)

    # remove spaces for comparison b/c we removed them in the grammar
    ground_truth = "SELECT col_1 from table_1 where col_1 = 1".replace(" ", "")

    assert content.strip() == ground_truth

@pytest.mark.asyncio
@allure.title("文本补全_判断guided_decoding_type错误") 
async def test_guided_decoding_type_error(sample_json_schema, sample_regex, client):
    with pytest.raises(openai.BadRequestError):
        _ = await client.completions.create(
            model=os_env('MODEL'),
            prompt="Give an example JSON that fits this schema: 42",
            extra_body=dict(guided_json=42,
                            guided_decoding_backend=guided_decoding_backend))

    with pytest.raises(openai.BadRequestError):
        _ = await client.completions.create(
            model=os_env('MODEL'),
            prompt="Give an example string that fits this regex",
            extra_body=dict(guided_regex=sample_regex,
                            guided_json=sample_json_schema))
