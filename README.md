# FastAPI + llama.cpp CPU Chatbot Template

Ubuntu **CPU 서버**에서 **llama.cpp** 기반 GGUF 모델을 실행하고,  
**FastAPI**로 웹/API 서버를 제공하는 챗봇 템플릿입니다.

기존 저장소가 **macOS Apple Silicon + MLX-LM** 기준으로 작성되어 있다면,
이 버전은 **학생들이 Ubuntu 서버에서 바로 실습/배포**할 수 있도록 CPU 기준으로 정리한 버전입니다.

## 관련 개념 먼저

### 1) MLX-LM 과 llama.cpp 차이
- **MLX-LM**: Apple Silicon(M 시리즈) 최적화 중심
- **llama.cpp**: Linux/Windows/macOS 전반에서 폭넓게 사용 가능
- **CPU 서버**에서는 보통 **GGUF + llama.cpp** 조합이 가장 단순함

### 2) 왜 GGUF를 쓰는가
- CPU 추론용으로 많이 쓰는 모델 포맷
- Q4, Q5 같은 양자화 모델을 사용 가능
- 메모리 사용량을 줄이면서 실습 가능

### 3) 지금 구조에서 바뀌는 점
기존:
```text
User → Web UI → FastAPI → MLX-LM
```

변경:
```text
User → Web UI → FastAPI → llama.cpp(GGUF)
User → Web UI → FastAPI → PostgreSQL(pgvector) → RAG(optional)
```

---

## 1. 권장 실습 환경

### 최소 권장
- Ubuntu 22.04 또는 24.04
- vCPU 4 이상
- 메모리 16GB 이상

### 현재 형님 환경 기준 권장
- Ubuntu 서버
- **8 vCPU / 32GB RAM**
- 모델: **Qwen2.5-7B-Instruct Q4_K_M GGUF**

이 환경이면 학생 실습용으로 무난합니다.

---

## 2. 디렉토리 구조

```text
llm-chatbot-template
├── fastapi-app
│   ├── main.py
│   ├── requirements.txt
│   └── .env.example
├── nginx
├── rag
├── scripts
├── deploy
│   └── fastapi.service
├── docs
├── web
├── data
│   ├── raw
│   ├── derived
│   ├── sql
│   └── docs
├── README.md
└── .env.example
```

---

## 3. Ubuntu 서버 초기 준비

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip build-essential cmake pkg-config git curl
```

### 작업 디렉토리 예시
```bash
sudo mkdir -p /opt/fastapi-llm-chatbot
sudo chown -R $USER:$USER /opt/fastapi-llm-chatbot
cd /opt/fastapi-llm-chatbot
```

---

## 4. 저장소 다운로드

```bash
git clone https://github.com/MelodyFrogK/llm-chatbot-template.git
cd llm-chatbot-template
```

---

## 5. Python 가상환경 생성

```bash
cd fastapi-app
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
pip install -r requirements.txt
```

### 다시 진입
```bash
cd /opt/fastapi-llm-chatbot/llm-chatbot-template/fastapi-app
source .venv/bin/activate
```

### 종료
```bash
deactivate
```

---

## 6. GGUF 모델 준비

### 모델 저장 디렉토리 생성
```bash
sudo mkdir -p /opt/models
sudo chown -R $USER:$USER /opt/models
```

### 다운로드 예시
아래는 예시입니다. 실제 URL은 사용하는 모델 배포 위치에 맞게 조정합니다.

```bash
cd /opt/models
wget -O Qwen2.5-7B-Instruct-Q4_K_M.gguf "GGUF_다운로드_URL"
```

파일이 준비되면 최종 경로 예시는 다음과 같습니다.

```text
/opt/models/Qwen2.5-7B-Instruct-Q4_K_M.gguf
```

---

## 7. 환경파일 생성

루트와 fastapi-app 둘 중 하나만 운영 기준으로 써도 되지만,
현재 코드 구조상 **fastapi-app/.env** 기준으로 두는 것을 권장합니다.

```bash
cd /opt/fastapi-llm-chatbot/llm-chatbot-template
cp .env.example fastapi-app/.env
```

### `.env` 예시
```env
APP_NAME=fastapi-llamacpp-chatbot
FASTAPI_HOST=0.0.0.0
FASTAPI_PORT=8000

LLM_MODEL_PATH=/opt/models/Qwen2.5-7B-Instruct-Q4_K_M.gguf
LLM_MAX_TOKENS=512
LLM_TEMPERATURE=0.7
LLM_CTX=8192
LLM_THREADS=8
LLM_N_GPU_LAYERS=0
LLM_BATCH=512

EMBED_MODEL_NAME=intfloat/multilingual-e5-large

RAG_ENABLED=false
RAG_BASE_URL=http://127.0.0.1:8100
RAG_TOP_K=5
RAG_TOP_K_WIDE=30
```

---

## 8. llama.cpp 모델 단독 테스트

```bash
cd /opt/fastapi-llm-chatbot/llm-chatbot-template/fastapi-app
source .venv/bin/activate
python3 - <<'PY'
from llama_cpp import Llama

llm = Llama(
    model_path="/opt/models/Qwen2.5-7B-Instruct-Q4_K_M.gguf",
    n_ctx=4096,
    n_threads=8,
    n_gpu_layers=0,
    verbose=False,
)

result = llm.create_chat_completion(
    messages=[
        {"role": "system", "content": "당신은 한국어로 답변하는 챗봇입니다."},
        {"role": "user", "content": "안녕하세요. 짧게 인사해줘."},
    ],
    temperature=0.7,
    max_tokens=128,
)

print(result["choices"][0]["message"]["content"])
PY
```

정상 동작하면 한국어 응답이 출력됩니다.

---

## 9. FastAPI 실행

```bash
cd /opt/fastapi-llm-chatbot/llm-chatbot-template/fastapi-app
source .venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8000
```

### 확인
- Swagger UI: `http://서버IP:8000/docs`
- Health Check: `http://서버IP:8000/health`
- Web UI: `http://서버IP:8000`

---

## 10. Chat API 테스트

```bash
curl -X POST http://127.0.0.1:8000/chat \
-H "Content-Type: application/json" \
-d '{"message":"안녕하세요. 한글로 자기소개 해줘.","use_rag":false,"history":[]}'
```

응답 예시:
```json
{
  "model_path": "/opt/models/Qwen2.5-7B-Instruct-Q4_K_M.gguf",
  "response": "안녕하세요. 질문에 답변을 도와드리는 로컬 챗봇입니다.",
  "sources": [],
  "search_query": "안녕하세요. 한글로 자기소개 해줘.",
  "top_k": 5
}
```

---

## 11. Web UI 테스트

브라우저에서 질문을 입력하고 FastAPI 응답을 받을 수 있습니다.

동작 구조:
```text
Browser → /chat → FastAPI → llama.cpp
```

현재 Web UI 기능:
- 채팅형 입력/응답
- Enter 전송
- 한글 조합 중복 전송 방지
- 프론트엔드 history 저장 기반 문맥 유지

---

## 12. systemd 서비스 등록

### 서비스 파일 복사
```bash
sudo cp deploy/fastapi.service /etc/systemd/system/fastapi.service
```

### 경로 확인
`deploy/fastapi.service` 안의 경로는 아래처럼 실제 경로와 맞춰야 합니다.

- `WorkingDirectory=/opt/fastapi-llm-chatbot/llm-chatbot-template/fastapi-app`
- `EnvironmentFile=/opt/fastapi-llm-chatbot/llm-chatbot-template/fastapi-app/.env`
- `ExecStart=/opt/fastapi-llm-chatbot/llm-chatbot-template/fastapi-app/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000`

### 적용
```bash
sudo systemctl daemon-reload
sudo systemctl enable fastapi
sudo systemctl start fastapi
sudo systemctl status fastapi
```

### 로그 확인
```bash
journalctl -u fastapi -f
```

---

## 13. RAG 사용 시 추가 패키지

현재 코드에서 RAG를 쓰려면 아래 패키지가 필요합니다.

- `sentence-transformers`
- `psycopg2-binary`

이 버전의 `requirements.txt` 에 이미 포함했습니다.

---

## 14. 학생 실습 순서

### Lab 1. Ubuntu 기본 패키지 설치
### Lab 2. 저장소 clone
### Lab 3. Python 가상환경 생성
### Lab 4. GGUF 모델 다운로드
### Lab 5. `.env` 설정
### Lab 6. llama.cpp 단독 테스트
### Lab 7. FastAPI 실행
### Lab 8. `/health`, `/chat` 테스트
### Lab 9. Web UI 테스트
### Lab 10. PostgreSQL + pgvector 연결
### Lab 11. RAG 문서 적재
### Lab 12. RAG 질의 테스트
### Lab 13. systemd 서비스 등록
### Lab 14. Nginx reverse proxy 연동

---

## 15. 자주 발생하는 문제

### `ModuleNotFoundError: No module named 'llama_cpp'`
```bash
cd fastapi-app
source .venv/bin/activate
pip install -r requirements.txt
```

### `FileNotFoundError: LLM model file not found`
`.env` 의 `LLM_MODEL_PATH` 경로가 실제 GGUF 파일 경로와 다릅니다.

```bash
ls -lh /opt/models
```

### `This model does not support chat completion`
일부 GGUF 모델은 채팅 템플릿 메타데이터가 부족할 수 있습니다.  
가능하면 **Instruct 계열 GGUF 모델**을 사용합니다.

### 응답이 너무 느림
- 모델이 너무 큼
- `LLM_THREADS` 가 너무 작음
- `LLM_CTX` 가 과도하게 큼

학생 실습용이면 먼저 아래처럼 시작하는 것이 무난합니다.

```env
LLM_CTX=4096
LLM_THREADS=8
LLM_MAX_TOKENS=256
```

### 메모리 부족
7B 모델보다 큰 모델을 CPU 서버에서 바로 쓰면 RAM 부담이 커질 수 있습니다.  
학생 실습은 **7B Q4_K_M**부터 시작하는 것이 안정적입니다.

### `/chat` 접속 시 `Method Not Allowed`
`/chat` 은 POST 전용입니다.  
브라우저 주소창으로 직접 열지 말고 `/docs`, `curl`, Web UI 로 테스트합니다.

---

## 16. 운영 방향

권장 구조:

```text
개발/실습: Ubuntu + FastAPI + llama.cpp + GGUF
운영: Linux VM + Nginx + FastAPI + PostgreSQL(pgvector) + 별도 추론 엔진 분리 가능
```

즉,
- 학생 실습/소규모 배포: **llama.cpp**
- 대규모 운영/병렬 처리 증가 시: **vLLM 등 별도 추론 서버** 검토

---

## 17. Git 반영 예시

```bash
git add .
git commit -m "Switch from MLX-LM to llama.cpp for Ubuntu CPU deployment"
git push
```
