# slack-agent-bot

![Runtime](https://img.shields.io/badge/Runtime-Python%203.11-3776AB?logo=python)
![Integration](https://img.shields.io/badge/Integration-Slack%20Events-4A154B?logo=slack)
![Pattern](https://img.shields.io/badge/Pattern-Webhook-yellow)
![Auth](https://img.shields.io/badge/Auth-Secrets%20Manager-DD344C)

Slack Events API webhook handler that receives file uploads, downloads from Slack, uploads to S3, and asynchronously invokes langchain-orchestrator. Uses AWS Secrets Manager for secure bot token storage with lazy loading.
