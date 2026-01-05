import pulumi

config=pulumi.Config()


app_name=config.require("appName")
env=config.require("env")

region="eu-north-1"
backend_port=8000


