import pytest
from openai import AsyncOpenAI
import os
from dynaconf import settings
from debugtalk import *
   
def pytest_addoption(parser):
    parser.addoption("--env", action="store", default="default", help="指定环境")

def pytest_sessionstart(session):
    env = session.config.getoption("env")
    settings.configure(INCLUDES_FOR_DYNACONF=['config/env_settings.toml'], FORCE_ENV_FOR_DYNACONF=env)
    os.environ["env_setting"] = env


    
@pytest.fixture
def client():
    if os_env('API_KEY'):
        client = AsyncOpenAI(
        # This is the default and can be omitted
        api_key=os_env('API_KEY'),
        base_url=os_env('BASE_URL')
        )
    else: 
        client = AsyncOpenAI(
        # This is the default and can be omitted
        api_key="-",
        base_url=os_env('BASE_URL')
        )
    return client

@pytest.fixture
def sample_regex():
    return (r"((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.){3}"
            r"(25[0-5]|(2[0-4]|1\d|[1-9]|)\d)")
    
@pytest.fixture
def sample_json_schema():
    return {
        "type": "object",
        "properties": {
            "name": {
                "type": "string"
            },
            "age": {
                "type": "integer"
            },
            "skills": {
                "type": "array",
                "items": {
                    "type": "string",
                    "maxLength": 10
                },
                "minItems": 3
            },
            "work_history": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "company": {
                            "type": "string"
                        },
                        "duration": {
                            "type": "number"
                        },
                        "position": {
                            "type": "string"
                        }
                    },
                    "required": ["company", "position"]
                }
            }
        },
        "required": ["name", "age", "skills", "work_history"]
    }

@pytest.fixture
def sample_guided_choice():
    return [
        "Python", "Java", "JavaScript", "C++", "C#", "PHP", "TypeScript",
        "Ruby", "Swift", "Kotlin"
    ]
@pytest.fixture
def sample_sql_statements():
    return ("""
start: select_statement
select_statement: "SELECT" column "from" table "where" condition
column: "col_1" | "col_2"
table: "table_1" | "table_2"
condition: column "=" number
number: "1" | "2"
""")