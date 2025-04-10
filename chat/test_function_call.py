from openai import OpenAI
import json
import pytest
import allure
from debugtalk import *

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
    
# TOOLS = [{
#     "type": "function",
#     "function": {
#         "name": "get_current_weather",
#         "description": "Get the current weather in a given location",
#         "parameters": {
#             "type": "object",
#             "properties": {
#                 "city": {
#                     "type":
#                     "string",
#                     "description":
#                     "The city to find the weather for, e.g. 'San Francisco'"
#                 },
#                 "state": {
#                     "type":
#                     "string",
#                     "description":
#                     "the two-letter abbreviation for the state that the city is"
#                     " in, e.g. 'CA' which would mean 'California'"
#                 },
#                 "unit": {
#                     "type": "string",
#                     "description": "The unit to fetch the temperature in",
#                     "enum": ["celsius", "fahrenheit"]
#                 }
#             },
#             "required": ["city", "state", "unit"]
#         }
#     }
# }]

# MESSAGES = [{
#     "role": "user",
#     "content": "Hi! How are you doing today?"
# }, {
#     "role": "assistant",
#     "content": "I'm doing well! How can I help you?"
# }, {
#     "role":
#     "user",
#     "content":
#     "Can you tell me what the temperate will be in Dallas, in fahrenheit?"
# }]

# FUNC_NAME = "get_current_weather"
# FUNC_ARGS = """{"city": "Dallas", "state": "TX", "unit": "fahrenheit"}"""


# def extract_reasoning_and_calls(chunks: list):
#     reasoning_content = ""
#     tool_call_idx = -1
#     arguments = []
#     function_names = []
#     for chunk in chunks:
#         if chunk.choices[0].delta.tool_calls:
#             tool_call = chunk.choices[0].delta.tool_calls[0]
#             if tool_call.index != tool_call_idx:
#                 tool_call_idx = chunk.choices[0].delta.tool_calls[0].index
#                 arguments.append("")
#                 function_names.append("")

#             if tool_call.function:
#                 if tool_call.function.name:
#                     function_names[tool_call_idx] = tool_call.function.name

#                 if tool_call.function.arguments:
#                     arguments[tool_call_idx] += tool_call.function.arguments
#         else:
#             print('*'*50, chunk)
#             if hasattr(chunk.choices[0].delta, "reasoning_content"):
#                 reasoning_content += chunk.choices[0].delta.reasoning_content
#     return reasoning_content, arguments, function_names


# # test streaming
# def test_chat_streaming_of_tool_and_reasoning():
#     stream = client.chat.completions.create(
#         model=os_env('MODEL'),
#         messages=MESSAGES,
#         tools=TOOLS,
#         temperature=0.0,
#         stream=True,
#     )
#     chunks = []
#     for chunk in stream:
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

