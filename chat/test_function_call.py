from openai import OpenAI
import json
import pytest
import allure
from debugtalk import *
import openai

# Function will be used outside LLM
def get_weather(location: str, unit: str):
    print(f"\nGetting the weather for {location} in {unit}...")
    
    fake_weather_of_Dallas = "The weather is 98 degrees fahrenheit, with partlycloudy skies and a low chance of rain."
    fake_weather_of_SF = "Clouds giving way to sun Hi: 76° Tonight: Mainly clear early, then areas of low clouds forming Lo: 56°"
    
    if 'Francisco' in location :
        return fake_weather_of_SF
    elif 'Dallas' in location :
        return fake_weather_of_Dallas
    else :
        return "unknowm city"
TOOLS=[
        {
            "type": "function",
            "function": {
            "name": "get_current_weather",
            "description": "Get the current weather in a given location",
            "parameters": {
                "type": "object",
                "properties": {
                "location": {
                    "type": "string",
                    "description": "The city and state"
                },
                "format": {
                    "type": "string",
                    "enum": ["celsius", "fahrenheit"],
                    "description": "Temperature unit"
                }
                },
                "required": ["location", "format"]
            }
            }
        },
        {
            "type": "function",
            "function": {
            "name": "get_stock_price",
            "description": "Get the current stock price of a company",
            "parameters": {
                "type": "object",
                "properties": {
                "symbol": {
                    "type": "string",
                    "description": "Stock symbol"
                },
                "currency": {
                    "type": "string",
                    "enum": ["USD", "EUR", "JPY"],
                    "description": "Currency to display price"
                }
                },
                "required": ["symbol"]
            }
            }
        }
        ]
FUNC_NAME = "get_current_weather"
FUNC_ARGS = ['{"location": "Tokyo", "format": "celsius"}', '{"symbol": "AAPL", "currency": "USD"}']

# Tool_call procedure
@pytest.mark.asyncio
@allure.title("对话_判断调用tool返回结果正确，同时验证role为tool时正确处理") 
async def test_tool_call_infer(client) :
    # Prepare request-1 params
    function_name="get_weather"
    tools = [{
        "type": "function",
        "function": {
            "name": function_name,
            "description": "Get the current weather in a given location",
            "parameters": {
                "type": "object",
                "properties": {
                    "location": {"type": "string", "description": "City and state, e.g., 'San Francisco, CA'"},
                    "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
                },
                "required": ["location", "unit"]
            }
        }
    }]
    tool_choice={"type": "function", "function": {"name": function_name}}
    city = "San Francisco"
    # city = "Dallas"
    chat_prompt = [{"role": "user", "content": f"What's the weather like in {city}?"}]

    # Request-1
    response = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=chat_prompt,
        temperature=0,
        max_tokens=200,
        tools=tools,
        tool_choice=tool_choice
    )
    assert response.choices[0].message.function_call == None 
    assert response.choices[0].message.tool_calls[0].id != None
    assert response.choices[0].message.tool_calls[0].function.name == function_name
    assert response.choices[0].message.tool_calls[0].type == 'function'
    
    tool_call_ret = response.choices[0].message.tool_calls[0]
  
    # Call function with response-1
    weather_by_func = get_weather(**json.loads(tool_call_ret.function.arguments))

    # Prepare request-2 params
    # *system_prompt is needed in some case
    system_prompt = {
        "role": "system", 
        "content": "You are a helpful assistant with tool calling capabilities. When you receive a tool call response, use the output to format an answer to the orginal use question."
    }
    # append func call ret in request-2 params
    func_ret_in_prompt = {
        "role": "tool", 
        "content": weather_by_func,
        "tool_call_id": tool_call_ret.id
    }

    chat_prompt.append(system_prompt)
    chat_prompt.append(func_ret_in_prompt)

    # Request-2
    response = await client.chat.completions.create(
            messages=chat_prompt,
            temperature=0,
            max_tokens=200,
            model=os_env('MODEL'),
            )

    # print("\nFinal output : \n", response.choices[0].message.content)
    print(response.choices[0].message) 

@pytest.mark.asyncio
@allure.title("对话_tool_choice传值为none返回结果正确，非stream模式") 
async def test_tool_call_none(client) :
    completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
            {
                "role": "user",
                "content": "What is the weather in Tokyo and the stock price of Apple?"
            }
        ],
        tools=TOOLS,
        tool_choice="none"
    )
    assert not completion.choices[0].message.tool_calls
    assert completion.choices[0].message.content != None
    
@pytest.mark.asyncio
@allure.title("对话_tool_choice为None返回400参数错误，非stream模式") 
async def test_tool_call_null(client) :
    try:
        completion = await client.chat.completions.create(
            model=os_env('MODEL'),
            messages=[
                {
                    "role": "user",
                    "content": "What is the weather in Tokyo and the stock price of Apple?"
                }
            ],
            tools=TOOLS,
            tool_choice=None
        )
        print(completion)
    except openai.BadRequestError as e:
        assert e.status_code == 400
        assert "Value error" in e.response.content.decode()
    else:
        pytest.fail("未按预期处理")
        
@pytest.mark.asyncio
@allure.title("对话_tool_choice为None返回400参数错误，stream模式") 
async def test_tool_call_null_stream(client) :
    try:
        completion = await client.chat.completions.create(
            model=os_env('MODEL'),
            stream=True,
            messages=[
                {
                    "role": "user",
                    "content": "What is the weather in Tokyo and the stock price of Apple?"
                }
            ],
            tools=TOOLS,
            tool_choice=None
        )
        print(completion)
    except openai.BadRequestError as e:
        assert e.status_code == 400
        assert "Value error" in e.response.content.decode()
        
    else:
        pytest.fail("未按预期处理")

@pytest.mark.asyncio
@allure.title("对话_tool_choice为''或'tool'返回400,参数不符合规范，非stream模式") 
async def test_tool_call_error(client) :
    try:
        await client.chat.completions.create(
            model=os_env('MODEL'),
            messages=[
                {
                    "role": "user",
                    "content": "What is the weather in Tokyo and the stock price of Apple?"
                }
            ],
            tools=TOOLS,
            tool_choice=""
        )
    except openai.BadRequestError as e:
        assert e.status_code == 400
        assert "value_error" in e.response.content.decode()
    try:
        await client.chat.completions.create(
            model=os_env('MODEL'),
            messages=[
                {
                    "role": "user",
                    "content": "What is the weather in Tokyo and the stock price of Apple?"
                }
            ],
            tools=TOOLS,
            tool_choice="tool"
        )
    except openai.BadRequestError as e:
        assert e.status_code == 400
        assert "value_error" in e.response.content.decode()
               
@pytest.mark.asyncio
@allure.title("对话_判断调用auto tool返回结果正确，非stream模式") 
async def test_tool_call_auto(client) :
    completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
            {
                "role": "user",
                "content": "What is the weather in Tokyo and the stock price of Apple?"
            }
        ],
        tools=TOOLS,
        tool_choice="auto"
    )
    
    if not completion.choices[0].message.tool_calls:
        print("未调用任何function")
    else:
        for tool_call in completion.choices[0].message.tool_calls:
            assert tool_call.function.name != None
            assert tool_call.function.name in ["get_current_weather","get_stock_price"]
            assert tool_call.function.arguments != None

@pytest.mark.asyncio
@allure.title("对话_判断调用required tool返回结果正确，非stream模式") 
async def test_tool_call_required(client) :
    completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
            {
                "role": "user",
                "content": "What is the weather in Tokyo and the stock price of Apple?"
            }
        ],
        tools=TOOLS,
        tool_choice="required"
    )
    
    assert len(completion.choices[0].message.tool_calls) >= 1
    for tool_call in completion.choices[0].message.tool_calls:
        assert tool_call.function.name != None
        assert tool_call.function.name in ["get_current_weather","get_stock_price"]
        assert tool_call.function.arguments != None

@pytest.mark.asyncio
@allure.title("对话_tool_choice传值为none返回结果正确，stream模式") 
async def test_tool_call_none_stream(client) :
    completion_not_stream = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
            {
                "role": "user",
                "content": "What is the weather in Tokyo and the stock price of Apple?"
            }
        ],
        tools=TOOLS,
        tool_choice="none",
        temperature=0
    )
    content_not_stream = completion_not_stream.choices[0].message.content
    
    completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        stream=True,
        messages=[
            {
                "role": "user",
                "content": "What is the weather in Tokyo and the stock price of Apple?"
            }
        ],
        tools=TOOLS,
        tool_choice="none",
        temperature=0
        
    )
    chunks = []
    async for chunk in completion:
        chunks.append(chunk)
    reasoning_content, arguments, function_names = extract_reasoning_and_calls(chunks)
    assert len(function_names) == 0
    assert reasoning_content.rstrip() == content_not_stream.rstrip()
    
@pytest.mark.asyncio
@allure.title("对话_tool_choice为''或'tool'返回400,参数不符合规范，stream模式") 
async def test_tool_call_error_stream(client) :
    try:
        await client.chat.completions.create(
            model=os_env('MODEL'),
            stream=True,
            messages=[
                {
                    "role": "user",
                    "content": "What is the weather in Tokyo and the stock price of Apple?"
                }
            ],
            tools=TOOLS,
            tool_choice=""
        )
    except openai.BadRequestError as e:
        assert e.status_code == 400
        assert "value_error" in e.response.content.decode()
    try:
        await client.chat.completions.create(
            model=os_env('MODEL'),
            stream=True,
            messages=[
                {
                    "role": "user",
                    "content": "What is the weather in Tokyo and the stock price of Apple?"
                }
            ],
            tools=TOOLS,
            tool_choice="tool"
        )
    except openai.BadRequestError as e:
        assert e.status_code == 400
        assert "value_error" in e.response.content.decode()
        
@pytest.mark.asyncio
@allure.title("对话_判断调用auto tool返回结果正确，stream模式") 
async def test_tool_call_auto_stream(client) :
    completion_not_stream = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
            {
                "role": "user",
                "content": "What is the weather in Tokyo and the stock price of Apple?"
            }
        ],
        tools=TOOLS,
        tool_choice="auto",
        temperature=0
    )
    content_not_stream = completion_not_stream.choices[0].message.content
    completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        stream=True,
        messages=[
            {
                "role": "user",
                "content": "What is the weather in Tokyo and the stock price of Apple?"
            }
        ],
        tools=TOOLS,
        tool_choice="auto",
        temperature=0
    )
    chunks = []
    async for chunk in completion:
        chunks.append(chunk)
    reasoning_content, arguments, function_names = extract_reasoning_and_calls(chunks)
    for function in function_names:
        assert function in ['get_current_weather', 'get_stock_price']
    assert reasoning_content.rstrip() == content_not_stream.rstrip()
    print(content_not_stream)
    print("*******************stream result*************************")
    print(reasoning_content)
    
    if not function_names:
        print("未调用任何function")
    else:
        for function in function_names:
            assert function != None
            assert function in ['get_current_weather', 'get_stock_price']
        for argument in arguments:
            assert argument != None
            
    
@pytest.mark.asyncio
@allure.title("对话_判断调用required tool返回结果正确，stream模式") 
async def test_tool_call_required_stream(client) :
    completion_not_stream = await client.chat.completions.create(
        model=os_env('MODEL'),
        messages=[
            {
                "role": "user",
                "content": "What is the weather in Tokyo and the stock price of Apple?"
            }
        ],
        tools=TOOLS,
        tool_choice="required"
    )
    content_not_stream = completion_not_stream.choices[0].message.content
    
    completion = await client.chat.completions.create(
        model=os_env('MODEL'),
        stream=True,
        messages=[
            {
                "role": "user",
                "content": "What is the weather in Tokyo and the stock price of Apple?"
            }
        ],
        tools=TOOLS,
        tool_choice="required"
    )
    chunks = []
    async for chunk in completion:
        chunks.append(chunk)
    reasoning_content, arguments, function_names = extract_reasoning_and_calls(chunks)
    assert len(function_names) >= 1
    for function in function_names:
        assert function in ['get_current_weather', 'get_stock_price']
    assert reasoning_content.rstrip() == content_not_stream.rstrip()

def extract_reasoning_and_calls(chunks: list):
    reasoning_content = ""
    arguments = []
    function_names = []
    for chunk in chunks:
        # 检查是否有 tool_calls
        if hasattr(chunk.choices[0].delta, "tool_calls") and chunk.choices[0].delta.tool_calls:
            for tool_call in chunk.choices[0].delta.tool_calls:
                # 确保索引在范围内
                while len(arguments) <= tool_call.index:
                    arguments.append("")
                while len(function_names) <= tool_call.index:
                    function_names.append("")
                
                # 更新 function name
                if hasattr(tool_call.function, "name") and tool_call.function.name:
                    function_names[tool_call.index] = tool_call.function.name
                
                # 更新 arguments
                if hasattr(tool_call.function, "arguments") and tool_call.function.arguments:
                    arguments[tool_call.index] += tool_call.function.arguments
        
        # 检查是否有 reasoning_content
        if hasattr(chunk.choices[0].delta, "content") and chunk.choices[0].delta.content:
            reasoning_content += chunk.choices[0].delta.content
    arguments = [x for x in arguments if x != '']
    function_names = [x for x in function_names if x != '']
    # print(reasoning_content)
    # print(arguments)
    # print(function_names)
    return reasoning_content, arguments, function_names


# # test streaming
# @pytest.mark.asyncio
# @allure.title("对话_判断调用required tool返回结果正确，stream模式") 
# async def test_chat_streaming_of_tool_and_reasoning(client):
#     stream = await client.chat.completions.create(
#         model=os_env('MODEL'),
#         messages=MESSAGES,
#         tools=TOOLS,
#         temperature=0.0,
#         stream=True,
#     )
#     chunks = []
#     async for chunk in stream:
#         chunks.append(chunk)
        
#     # print(chunks)
#     reasoning_content, arguments, function_names = extract_reasoning_and_calls(chunks)
#     assert len(reasoning_content) > 0
#     assert len(function_names) > 0 and function_names[0] == FUNC_NAME
#     assert len(arguments) > 0 and arguments[0] == FUNC_ARGS


# # test full generate
# async def test_chat_full_of_tool_and_reasoning():
#     tool_calls = client.chat.completions.create(
#         model=os_env('MODEL'),
#         messages=MESSAGES,
#         tools=TOOLS,
#         temperature=0.0,
#         stream=False,
#     )

#     assert len(tool_calls.choices[0].message.reasoning_content) > 0
#     assert tool_calls.choices[0].message.tool_calls[0].function.name == FUNC_NAME
#     assert tool_calls.choices[0].message.tool_calls[0].function.arguments == FUNC_ARGS

