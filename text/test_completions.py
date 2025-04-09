import os
from openai import OpenAI
import pytest
import allure
from openai import BadRequestError


client = OpenAI(
    # This is the default and can be omitted
    api_key="-",
    base_url="http://10.208.130.44:2025/v1"
)
model = "deepseek"

def stop_text(text,stop):
    return text.split(stop)[0]
    

@pytest.fixture
@allure.title("文本补全_判断非stream模式输出结果正确")
def test_sample_completions():
    completion = client.completions.create(
        model=model,
        prompt="How do I check if a Python object is an instance of a class?",
        temperature=0
    )
    assert completion.object == 'text_completion'
    assert completion.id != None
    assert len(completion.choices) == 1
    assert completion.usage.completion_tokens <= 512
    no_stop_content = completion.choices[0].text
    no_stop_tokens = completion.usage.completion_tokens
    return no_stop_content,no_stop_tokens

@allure.title("文本补全_判断设置stop字符串时，输出结果正确")
def test_with_stop(test_sample_completions):
    stop_world = "Python"
    completion = client.completions.create(
        model=model,
        prompt="How do I check if a Python object is an instance of a class?",
        temperature=0,
        stop=[stop_world],
    )
    assert completion.id != None
    assert len(completion.choices) == 1
    assert completion.choices[0].finish_reason == 'stop'
    assert completion.usage.completion_tokens < 512
    assert test_sample_completions[0] != completion.choices[0].text
    assert test_sample_completions[1] > completion.usage.completion_tokens
    text = stop_text(test_sample_completions[0],stop_world)
    assert completion.choices[0].text == text

@allure.title("文本补全_判断温度不同返回结果改变")
def test_with_temperature_1(test_sample_completions):
    completion = client.completions.create(
        model=model,
        prompt="How do I check if a Python object is an instance of a class?",
        temperature=1,
    )
    assert completion.id != None
    assert len(completion.choices) == 1
    assert completion.usage.completion_tokens <= 512
    assert test_sample_completions[0] != completion.choices[0].text
    
@allure.title("文本补全_不设置max_tokens，使用束搜索")    
def test_with_beam_search_without_max_tokens():
    completion = client.completions.create(
        model=model,
        prompt="How do I check if a Python object is an instance of a class?",
        temperature=0,
        n=5,
        extra_body={
            "use_beam_search":True
        }
    )
    
    assert completion.id != None
    assert len(completion.choices) == 5

@allure.title("文本补全_判断设置max_tokens，使用束搜索")    
def test_with_beam_search_with_max_tokens():
    completion = client.completions.create(
        model=model,
        prompt="How do I check if a Python object is an instance of a class?",
        temperature=0,
        n=5,
        max_tokens=26,
        extra_body={
            "use_beam_search":True
        }
    )
    assert completion.id != None
    assert len(completion.choices) == 5
    text_0 = completion.choices[0].text
    text_1 = completion.choices[1].text
    text_2 = completion.choices[2].text
    text_3 = completion.choices[3].text
    text_4 = completion.choices[4].text
    assert text_0 != text_1 != text_2 != text_3 != text_4 != None

@allure.title("文本补全_判断设置max_tokens，返回结果正确")    
def test_completions_with_max_tokens():
    completion = client.completions.create(
        model=model,
        prompt="How do I check if a Python object is an instance of a class?",
        temperature=0,
        max_tokens=12
    )
    assert completion.id != None
    assert len(completion.choices) == 1
    assert completion.usage.completion_tokens <= 12
    assert completion.choices[0].finish_reason == 'length'

@allure.title("文本补全_判断prompt为token ids，返回结果正确")        
def test_with_token_ids():
    # test using token IDs
    completion = client.completions.create(
        model=model,
        prompt=[0, 0, 32000, 32001, 32002],
        echo=True,
        max_tokens=5,
        temperature=0.0,
    )
    # Added tokens should appear in tokenized prompt
    assert completion.object == 'text_completion'
    assert completion.choices[0].finish_reason == 'length'
    assert completion.choices[0].text != None

@allure.title("文本补全_判断stream模式返回结果正确")       
def test_completion_streaming():
    prompt = "What is an LLM?"
    single_completion = client.completions.create(
        model=model,
        prompt=prompt,
        max_tokens=5,
        temperature=0.0,
    )
    single_output = single_completion.choices[0].text
    stream = client.completions.create(
        model=model,
        prompt=prompt,
        max_tokens=5,
        temperature=0.0,
        stream=True)
    chunks: list[str] = []
    finish_reason_count = 0
    for chunk in stream:
        chunks.append(chunk.choices[0].text)
        if chunk.choices[0].finish_reason is not None:
            finish_reason_count += 1
    # finish reason should only return in last block
    assert finish_reason_count == 1
    assert chunk.choices[0].finish_reason == "length"
    assert chunk.choices[0].text
    assert "".join(chunks) == single_output

@allure.title("文本补全_判断n=3时，parallel_streaming回结果正确")        
def test_parallel_streaming():
    """Streaming for parallel sampling.
    The tokens from multiple samples, are flattened into a single stream,
    with an index to indicate which sample the token belongs to.
    """

    prompt = "What is an LLM?"
    n = 3
    max_tokens = 5

    stream = client.completions.create(
        model=model,
        prompt=prompt,
        max_tokens=max_tokens,
        n=n,
        stream=True)
    chunks: list[list[str]] = [[] for i in range(n)]
    finish_reason_count = 0
    for chunk in stream:
        index = chunk.choices[0].index
        text = chunk.choices[0].text
        chunks[index].append(text)
        if chunk.choices[0].finish_reason is not None:
            finish_reason_count += 1
    assert finish_reason_count == n
    for chunk in chunks:
        assert len(chunk) == max_tokens
        print("".join(chunk))
        
prompt = "What is the capital of France?"

@allure.title("文本补全_判断stream模式下，stream options全为false时返回结果正确")          
def test_completion_with_stream_options_all_false():
    # Test stream=True, stream_options=
    #     {"include_usage": False, "continuous_usage_stats": False}
    stream = client.completions.create(
        model=model,
        prompt=prompt,
        max_tokens=5,
        temperature=0.0,
        stream=True,
        stream_options={
            "include_usage": False,
            "continuous_usage_stats":False,
        })

    for chunk in stream:
        assert chunk.usage is None
        
@allure.title("文本补全_判断stream模式下，continuous_usage_stats为true时返回结果正确")  
def test_completion_with_continuous_usage_stats_true():
    # Test stream=True, stream_options=
    #     {"include_usage": False, "continuous_usage_stats": True}
    stream = client.completions.create(
        model=model,
        prompt=prompt,
        max_tokens=5,
        temperature=0.0,
        stream=True,
        stream_options={
            "include_usage": False,
            "continuous_usage_stats":True,
        })
    for chunk in stream:
        assert chunk.usage is None
        
@allure.title("文本补全_判断stream模式下，include_usage为true时返回结果正确")  
def test_completion_with_include_usage_true():
    # Test stream=True, stream_options=
    #     {"include_usage": True, "continuous_usage_stats": False}
    stream = client.completions.create(
        model=model,
        prompt=prompt,
        max_tokens=5,
        temperature=0.0,
        stream=True,
        stream_options={
            "include_usage": True,
            "continuous_usage_stats":False,
        })
    for chunk in stream:
        if chunk.choices[0].finish_reason is None:
            assert chunk.usage is None
        else:
            assert chunk.usage is None
            final_chunk = stream.__next__()
            assert final_chunk.usage is not None
            assert final_chunk.usage.prompt_tokens > 0
            assert final_chunk.usage.completion_tokens > 0
            assert final_chunk.usage.total_tokens == (
                final_chunk.usage.prompt_tokens +
                final_chunk.usage.completion_tokens)
            assert final_chunk.choices == []

    # Test stream=True, stream_options=
    #     {"include_usage": True, "continuous_usage_stats": True}
@allure.title("文本补全_判断stream模式下，stream_options全为true时返回结果正确")
def test_completion_with_stream_options_all_true():
    stream = client.completions.create(
        model=model,
        prompt=prompt,
        max_tokens=5,
        temperature=0.0,
        stream=True,
        stream_options={
            "include_usage": True,
            "continuous_usage_stats":True,
        })
    for chunk in stream:
        assert chunk.usage is not None
        assert chunk.usage.prompt_tokens > 0
        assert chunk.usage.completion_tokens > 0
        assert chunk.usage.total_tokens == (chunk.usage.prompt_tokens +
                                            chunk.usage.completion_tokens)
        if chunk.choices[0].finish_reason is not None:
            final_chunk = stream.__next__()
            assert final_chunk.usage is not None
            assert final_chunk.usage.prompt_tokens > 0
            assert final_chunk.usage.completion_tokens > 0
            assert final_chunk.usage.total_tokens == (
                final_chunk.usage.prompt_tokens +
                final_chunk.usage.completion_tokens)
            assert final_chunk.choices == []

    # Test stream=False, stream_options=
    #     {"include_usage": None}
@allure.title("文本补全_判断非stream模式下，使用stream_options报400（4个组合）")
def test_completion_without_stream_use_options():
    with pytest.raises(BadRequestError):
        client.completions.create(
            model=model,
            prompt=prompt,
            max_tokens=5,
            temperature=0.0,
            stream=False,
            stream_options={"include_usage": None})

    # Test stream=False, stream_options=
    #    {"include_usage": True}
    with pytest.raises(BadRequestError):
        client.completions.create(
            model=model,
            prompt=prompt,
            max_tokens=5,
            temperature=0.0,
            stream=False,
            stream_options={"include_usage": True})

# Test stream=False, stream_options=
    #     {"continuous_usage_stats": None}
    with pytest.raises(BadRequestError):
        client.completions.create(
            model=model,
            prompt=prompt,
            max_tokens=5,
            temperature=0.0,
            stream=False,
            stream_options={"continuous_usage_stats": None})

    # Test stream=False, stream_options=
    #    {"continuous_usage_stats": True}
    with pytest.raises(BadRequestError):
        client.completions.create(
            model=model,
            prompt=prompt,
            max_tokens=5,
            temperature=0.0,
            stream=False,
            stream_options={"continuous_usage_stats": True})

@allure.title("文本补全_prompt为文本数组和token ids数组时batch_completions返回结果正确")      
def test_batch_completions():
    # test both text and token IDs
    #The prompt(s) to generate completions for, encoded as a string, array of strings, array of tokens, or array of token arrays.
    for prompts in (["Hello, my name is"] * 2, [[0, 0, 0, 0, 0]] * 2):
        # test simple list
        batch = client.completions.create(
            model=model,
            prompt=prompts,
            max_tokens=5,
            temperature=0.0,
        )
        print(batch)
        assert len(batch.choices) == 2
        assert batch.choices[0].text == batch.choices[1].text

        # test n = 2
        batch = client.completions.create(
            model=model,
            prompt=prompts,
            n=2,
            max_tokens=5,
            temperature=0.0,
            extra_body=dict(
                # NOTE: this has to be true for n > 1 in vLLM, but
                # not necessary for official client.
                use_beam_search=True),
        )
        assert len(batch.choices) == 4
        assert batch.choices[0].text != batch.choices[
            1].text, "beam search should be different"
        assert batch.choices[0].text == batch.choices[
            2].text, "two copies of the same prompt should be the same"
        assert batch.choices[1].text == batch.choices[
            3].text, "two copies of the same prompt should be the same"

        # test streaming
        batch = client.completions.create(
            model=model,
            prompt=prompts,
            max_tokens=5,
            temperature=0.0,
            stream=True,
        )
        texts = [""] * 2
        for chunk in batch:
            assert len(chunk.choices) == 1
            choice = chunk.choices[0]
            texts[choice.index] += choice.text
        assert texts[0] == texts[1]