from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from openpyxl import load_workbook
from openpyxl.utils import get_column_letter
from openpyxl.styles import Alignment,Font
import argparse
import subprocess

parser = argparse.ArgumentParser(description="汇总结果写入文件")
parser.add_argument('--file', type=str)
parser.add_argument('--email', type=str)
parser.add_argument('--env', type=str)
parser.add_argument('--url', type=str)
parser.add_argument('--model', type=str)
parser.add_argument('--gpu', type=str)
parser.add_argument('--cmd', type=str)

args=parser.parse_args()
file_name = args.file
emails = args.email
env = args.env
url = args.url
model = args.model
gpu = args.gpu
cmd = args.cmd

add_cmd = f"dynaconf write toml -v BASE_URL={url} -v MODEL={model} -v API_KEY=- -p config/env_settings.toml -e {env} -y"
subprocess.run(add_cmd, shell=True)
