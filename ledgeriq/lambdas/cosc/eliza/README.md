# eliza

ELIZA chatbot Lambda using [oureliza](https://pypi.org/project/oureliza/).

## Endpoint

```
https://421zhfcf67.execute-api.us-west-2.amazonaws.com/prod/eliza_get
```

## API

### Get opening greeting
```
GET ?action=initial
```
```json
{"action": "initial", "response": "Hello. What brings you here today?"}
```

### Chat with ELIZA
```
GET ?text=I feel sad today
```
```json
{"text": "I feel sad today", "response": "What brings about these feelings?"}
```

### Get closing message
```
GET ?action=final
```
```json
{"action": "final", "response": "Until next time. Be well."}
```
