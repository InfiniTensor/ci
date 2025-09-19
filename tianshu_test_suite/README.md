## 使用方法 ##
进入tianshu_test_suite目录，执行:
    bash tianshu_resource_monitor.sh s_yangshuo Smoke main-98e050eb
    bash tianshu_resource_monitor.sh s_yangshuo Performance <Random|SharedGPT> main-98e050eb

参数1: 服务器上的用户名
参数2: 测试类型，分为Smoke、Performance、Stability、Accuracy
参数3：测试参数，比如Performance测试类型对应的Random或SharedGPT
参数2：测试版本（镜像tag），如果为空，则默认为Latest
