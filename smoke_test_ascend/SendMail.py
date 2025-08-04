import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders

def send_email(sender_email, sender_password, receiver_email, subject, body, attachment_path):
    # 创建邮件对象
    msg = MIMEMultipart()
    msg['From'] = sender_email
    msg['To'] = receiver_email
    msg['Subject'] = subject

    # 添加邮件正文
    msg.attach(MIMEText(body, 'plain'))

    # 添加附件
    with open(attachment_path, 'rb') as attachment:
        part = MIMEBase('application', 'octet-stream')
        part.set_payload(attachment.read())
    
    # 编码附件
    encoders.encode_base64(part)
    
    # 设置附件头信息
    part.add_header(
        'Content-Disposition',
        f'attachment; filename= {attachment_path.split("/")[-1]}'
    )
    
    # 将附件添加到邮件
    msg.attach(part)

    try:
        # 连接 SMTP 服务器（以 Gmail 为例）
        server = smtplib.SMTP('smtp.gmail.com', 587)
        server.starttls()  # 启用 TLS
        server.login(sender_email, sender_password)
        
        # 发送邮件
        server.send_message(msg)
        print("邮件发送成功！")
        
    except Exception as e:
        print(f"发送邮件失败: {e}")
        
    finally:
        server.quit()

# 使用示例
sender_email = "your_email@gmail.com"  # 替换为你的邮箱
sender_password = "your_password"      # 替换为你的邮箱密码或应用专用密码
receiver_email = "recipient@example.com"  # 替换为收件人邮箱
subject = "测试邮件 - 带附件"
body = "这是一封带附件的测试邮件。"
attachment_path = "path/to/your/file.pdf"  # 替换为附件文件路径

send_email(sender_email, sender_password, receiver_email, subject, body, attachment_path)
