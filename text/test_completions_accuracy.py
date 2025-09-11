import os
from openai import OpenAI
import pytest
from openai.types.chat import ChatCompletionChunk,ChatCompletion
from openai.types import Completion

from openai import AsyncStream
import openai
import allure
from debugtalk import *
from collections import Counter

QUESTION="Question: Angelo and Melanie want to plan how many hours over the next week they should study together for their test next week. They have 2 chapters of their textbook to study and 4 worksheets to memorize. They figure out that they should dedicate 3 hours to each chapter of their textbook and 1.5 hours for each worksheet. If they plan to study no more than 4 hours each day, how many days should they plan to study total over the next week if they take a 10-minute break every hour, include 3 10-minute snack breaks each day, and 30 minutes for lunch each day?\nLet's think step by step\nAnswer:\nAngelo and Melanie think they should dedicate 3 hours to each of the 2 chapters, 3 hours x 2 chapters = 6 hours total.\nFor the worksheets they plan to dedicate 1.5 hours for each worksheet, 1.5 hours x 4 worksheets = 6 hours total.\nAngelo and Melanie need to start with planning 12 hours to study, at 4 hours a day, 12 / 4 = 3 days.\nHowever, they need to include time for breaks and lunch. Every hour they want to include a 10-minute break, so 12 total hours x 10 minutes = 120 extra minutes for breaks.\nThey also want to include 3 10-minute snack breaks, 3 x 10 minutes = 30 minutes.\nAnd they want to include 30 minutes for lunch each day, so 120 minutes for breaks + 30 minutes for snack breaks + 30 minutes for lunch = 180 minutes, or 180 / 60 minutes per hour = 3 extra hours.\nSo Angelo and Melanie want to plan 12 hours to study + 3 hours of breaks = 15 hours total.\nThey want to study no more than 4 hours each day, 15 hours / 4 hours each day = 3.75\nThey will need to plan to study 4 days to allow for all the time they need.\nThe answer is 4\n\nQuestion: Mark's basketball team scores 25 2 pointers, 8 3 pointers and 10 free throws.  Their opponents score double the 2 pointers but half the 3 pointers and free throws.  What's the total number of points scored by both teams added together?\nLet's think step by step\nAnswer:\nMark's team scores 25 2 pointers, meaning they scored 25*2= 50 points in 2 pointers.\nHis team also scores 6 3 pointers, meaning they scored 8*3= 24 points in 3 pointers\nThey scored 10 free throws, and free throws count as one point so they scored 10*1=10 points in free throws.\nAll together his team scored 50+24+10= 84 points\nMark's opponents scored double his team's number of 2 pointers, meaning they scored 50*2=100 points in 2 pointers.\nHis opponents scored half his team's number of 3 pointers, meaning they scored 24/2= 12 points in 3 pointers.\nThey also scored half Mark's team's points in free throws, meaning they scored 10/2=5 points in free throws.\nAll together Mark's opponents scored 100+12+5=117 points\nThe total score for the game is both team's scores added together, so it is 84+117=201 points\nThe answer is 201\n\nQuestion: Bella has two times as many marbles as frisbees. She also has 20 more frisbees than deck cards. If she buys 2/5 times more of each item, what would be the total number of the items she will have if she currently has 60 marbles?\nLet's think step by step\nAnswer:\nWhen Bella buys 2/5 times more marbles, she'll have increased the number of marbles by 2/5*60 = 24\nThe total number of marbles she'll have is 60+24 = 84\nIf Bella currently has 60 marbles, and she has two times as many marbles as frisbees, she has 60/2 = 30 frisbees.\nIf Bella buys 2/5 times more frisbees, she'll have 2/5*30 = 12 more frisbees.\nThe total number of frisbees she'll have will increase to 30+12 = 42\nBella also has 20 more frisbees than deck cards, meaning she has 30-20 = 10 deck cards\nIf she buys 2/5 times more deck cards, she'll have 2/5*10 = 4 more deck cards.\nThe total number of deck cards she'll have is 10+4 = 14\nTogether, Bella will have a total of 14+42+84 = 140 items\nThe answer is 140\n\nQuestion: A group of 4 fruit baskets contains 9 apples, 15 oranges, and 14 bananas in the first three baskets and 2 less of each fruit in the fourth basket. How many fruits are there?\nLet's think step by step\nAnswer:\nFor the first three baskets, the number of apples and oranges in one basket is 9+15=24\nIn total, together with bananas, the number of fruits in one basket is 24+14=38 for the first three baskets.\nSince there are three baskets each having 38 fruits, there are 3*38=114 fruits in the first three baskets.\nThe number of apples in the fourth basket is 9-2=7\nThere are also 15-2=13 oranges in the fourth basket\nThe combined number of oranges and apples in the fourth basket is 13+7=20\nThe fourth basket also contains 14-2=12 bananas.\nIn total, the fourth basket has 20+12=32 fruits.\nThe four baskets together have 32+114=146 fruits.\nThe answer is 146\n\nQuestion: Anthony had 50 pencils. He gave 1/2 of his pencils to Brandon, and he gave 3/5 of the remaining pencils to Charlie. He kept the remaining pencils. How many pencils did Anthony keep?\nLet's think step by step\nAnswer:"
def text_accuracy(text,repeat=5):
    if len(text) < repeat:
        return True  # 长度<5，不可能有5个连续重复
    
    current_char = None
    count = 1
    
    for c in text:
        if c == current_char:
            count += 1
            if count >= repeat and (c.isdigit() or c.isalpha()):
                print('*'*50,current_char)
                return False
        else:
            current_char = c
            count = 1
    
    return True
def is_nonsense_text(text: str, min_repeat=3, max_ratio=0.5) -> bool:
    """
    判断文本是否无意义（基于重复模式）
    :param text: 待检测文本
    :param min_repeat: 最小重复次数（如 "HEMA" 重复3次以上视为无意义）
    :param max_ratio: 重复部分占全文的最大允许比例（超过则认为无意义）
    :return: True（无意义） / False（有意义）
    """
    n = len(text)
    # 统计所有可能重复的子串
    substrings = [text[i:j] for i in range(n) for j in range(i+1, min(i+10, n)+1)]  # 限制子串长度≤10
    freq = Counter(substrings)
    
    # 检查是否有子串重复次数≥min_repeat，且占比超过max_ratio
    for substr, count in freq.items():
        if len(substr) * count > max_ratio * n and count >= min_repeat:
            return True
    return False
def is_low_diversity(text: str, min_unique_ratio=0.3) -> bool:
    """
    判断文本是否单词多样性过低
    :param min_unique_ratio: 唯一字符数占总字符数的最小比例（低于则视为无意义）
    """
    unique_words = len(set(text.split()))  # 不区分大小写
    return unique_words / len(text.split()) < min_unique_ratio
texts=[
        ("文本1","How to tell if a customer segment is well segmented? In 3 bullet points."),
        ("文本2","Tony Robbins describes six core human needs that drive our behaviors and motivations. These six needs are:\n\n1. Certainty: The need for safety, stability, and predictability. This includes the need for comfort, security, and control over our environment.\n2. Variety: The need for novelty, excitement, and change. This includes the need for adventure, stimulation, and new experiences.\n3. Significance: The need to feel important, special, and unique. This includes the need for recognition, achievement, and respect.\n4. Connection: The need for social connection and love. This includes the need for intimacy, belonging, and friendship.\n5. Growth: The need for personal growth and development. This includes the need for learning, self-improvement, and progress.\n6. Contribution: The need to make a positive impact in the world. This includes the need to give back, help others, and make a difference.\n\nAccording to Tony Robbins, these six needs are universal and apply to all individuals. Each person may prioritize these needs differently, and may fulfill them in different ways, but they are fundamental drivers of human behavior. By understanding these needs, individuals can gain insight into their own motivations and behaviors, and can use this knowledge to create a more fulfilling and meaningful life."),
        ("文本3","In Java, I want to replace string like \"This is a new {object} at {place}\" with a Map, {object: \"student\", \"point 3, 4\"}, and get a result \"This is a new student at point 3, 4\". How can I do?"),
        ("文本4","The language used to describe the addressing modes of these instructions is metaphorical and grandiose, emphasizing the complexity and power of these commands. For example, the use of \"enigmatic\" and \"confounding\" to describe JMP ABCD and MOV AX, [BX+SI], respectively, suggests that these instructions are not easily understood and require a level of expertise to comprehend.\n\nSimilarly, the use of \"inscrutable\" and \"cryptic\" to describe MOV AX, [100] and MOV AX, [BX], respectively, implies that these commands are shrouded in mystery and are difficult to decipher. The speaker's use of \"perplexing\" and \"unfathomable\" to describe MOV AX, [BX\\*2+SI] and MOV AX, BX, respectively, suggests that these commands are particularly challenging and require a deep understanding of the instruction set architecture.\n\nFinally, the use of \"enigmatic\" to describe MOV AX, 7 is particularly interesting, as this instruction simply moves the value 7 into the AX register. However, the language used to describe it suggests that even seemingly straightforward commands can be mysterious and awe-inspiring in the context of the larger instruction set.\n\nOverall, the use of metaphorical language to describe the addressing modes of these instructions serves to emphasize their complexity and power, while also imbuing them with a sense of wonder and admiration"),
        ("文本5","By the grace of the gods, the arcane and enigmatic art of metaphorical language has been summoned forth to shed light upon the bewildering addressing modes of the instructions before us. The orators have invoked grandiose expressions with utmost reverence and awe, extolling the inscrutable power and ineffable functionality of these directives. Among the labyrinthine commands are the confounding JMP ABCD, the abstruse MOV AX, [BX+SI], the unfathomable MOV AX, [100], the mystifying MOV AX, [BX], the perplexing MOV AX, [BX\\*2+SI], the enigmatic MOV AX, BX, and finally, the recondite MOV AX, 7.\n\nThe language used to describe these addressing modes is both perplexing and ornate, underscoring the prodigious complexity and esoteric power of these commands. The use of words like \"arcane,\" \"enigmatic,\" and \"ineffable\" imbues these instructions with an aura of almost mystical obscurity, requiring a level of expertise and mastery beyond the realm of mere mortals to unlock their true potential. Furthermore, the employment of terms such as \"abstruse,\" \"unfathomable,\" and \"recondite\" suggests that these commands are shrouded in an impenetrable veil of mystery, beckoning only the most erudite and astute of minds to unravel their hidden depths.\n\nThe speakers' use of metaphorical language serves to elevate these instructions to a level of veneration and reverence, infusing them with an almost sacred aura. Even the seemingly simple MOV AX, 7 is enshrined with the epithet \"enigmatic,\" underscoring the profound and awe-inspiring nature of the instruction set as a whole. Thus, the use of such ornate and enigmatic language in describing these addressing modes serves to amplify their mystique and enshroud them in an aura of intrigue and wonder, beckoning the most intrepid and enterprising of minds to unlock the secrets of this arcane realm.")
    ]
@pytest.mark.asyncio
@pytest.mark.timeout(180)
@pytest.mark.parametrize(
    "title,text",texts
    ,
)
@allure.title("文本补全_简单判断stream为false时，推理结果准确性: {title}")
async def test_chat_accuracy(client,text,title):
    # 判断stream为false时，返回为ChatCompletion类型
    completion = await client.completions.create(
        model=os_env('MODEL'),
        prompt=text,
        temperature=0,
        stream=False
    )
    print(title)
    assert completion.object == 'text_completion'
    assert isinstance(completion, Completion) == True
    print('*'*25 + '文本补全输出信息' +'*'*25,completion.usage)
    print('*'*25 + '文本补全停止原因' +'*'*25,completion.choices[0].finish_reason)
    assert is_nonsense_text(completion.choices[0].text, min_repeat=3, max_ratio=0.3) == False
    # assert is_low_diversity(completion.choices[0].text) == False
    assert text_accuracy(completion.choices[0].text) == True