# LLM Chatbot Template (CPU + RAG)

Ubuntu **CPU 서버**에서 **llama.cpp 기반 GGUF 모델**을 실행하고,  
**FastAPI + PostgreSQL(pgvector)** 로 **RAG 챗봇**을 구성하는 템플릿입니다.

이 README는 실제 구축 과정에서 발생했던 문제를 반영해,  
**학생들이 순서대로 따라 하면 동작하도록** 다시 정리한 버전입니다.

---

## 0. 전체 구조

```text
사용자
→ Web UI / curl
→ FastAPI
→ llama-cpp-python
→ GGUF 모델

(use_rag=true 인 경우)
→ 질문 임베딩
→ PostgreSQL(pgvector) 유사도 검색
→ 검색 문서 컨텍스트 구성
→ LLM 답변
```

---

## 1. 관련 개념 먼저

### 1-1. MLX-LM 과 llama.cpp 차이
- **MLX-LM**: Apple Silicon(M 시리즈) 중심
- **llama.cpp**: Linux / Windows / macOS 전반에서 사용 가능
- **Ubuntu CPU 서버**에서는 보통 **GGUF + llama.cpp** 조합이 가장 단순함

### 1-2. 왜 GGUF를 쓰는가
- CPU 추론에 많이 사용하는 모델 포맷
- Q4, Q5 양자화 모델 사용 가능
- 메모리 사용량을 줄여 실습하기 좋음

### 1-3. RAG란
RAG는 사용자의 질문을 벡터로 바꾸고,  
문서 DB에서 관련 문서를 먼저 찾은 뒤,  
그 문서를 LLM에게 같이 넘겨 답변 정확도를 높이는 방식입니다.

```text
질문 입력
→ 질문 임베딩 생성
→ pgvector 유사도 검색
→ 관련 문서 추출
→ 문서 내용을 LLM 프롬프트에 추가
→ 답변 생성
```

---

## 2. 권장 실습 환경

### 최소 권장
- Ubuntu 22.04 또는 24.04
- vCPU 4 이상
- RAM 16GB 이상

### 권장
- **8 vCPU / 32GB RAM**
- 모델: **Qwen2.5-7B-Instruct Q4_K_M GGUF**

---

## 3. 디렉토리 구조 예시

```text
llm-chatbot-template-cpu
├── fastapi-app
│   ├── main.py
│   ├── requirements.txt
│   └── .venv
├── rag
│   └── ingest_pgvector.py
├── data
│   ├── derived
│   │   └── rag_documents_seed.jsonl
│   └── sql
│       └── create_tables.sql
├── deploy
├── scripts
├── web
├── models
├── .env
├── .env.db
└── README.md
```

---

## 4. Ubuntu 서버 초기 준비

```bash
sudo apt update
sudo apt install -y \
  git \
  curl \
  wget \
  vim \
  unzip \
  build-essential \
  cmake \
  pkg-config \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  postgresql-client
```

---

## 5. 저장소 다운로드

```bash
git clone https://github.com/MelodyFrogK/llm-chatbot-template-cpu.git
cd llm-chatbot-template-cpu
```

---

## 6. Python 가상환경 생성

```bash
cd fastapi-app
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
pip install -r requirements.txt
```

### 다시 진입
```bash
cd ~/llm-chatbot-template-cpu/fastapi-app
source .venv/bin/activate
```

### 종료
```bash
deactivate
```

---

## 7. llama.cpp 설치

최근 Ubuntu 환경에서는 `make` 대신 **cmake 빌드** 방식이 더 안전합니다.

```bash
cd /root
rm -rf llama.cpp
git clone --depth=1 https://github.com/ggml-org/llama.cpp
cd llama.cpp

cmake -B build
cmake --build build --config Release -j"$(nproc)"
```

### 바이너리 확인
```bash
find /root/llama.cpp/build -type f | egrep 'llama-gguf-split|gguf-split'
```

보통 아래 둘 중 하나가 생성됩니다.

```text
/root/llama.cpp/build/bin/llama-gguf-split
/root/llama.cpp/build/bin/gguf-split
```

---

## 8. GGUF 모델 다운로드

### 8-1. models 폴더 준비
```bash
mkdir -p ~/llm-chatbot-template-cpu/models
cd ~/llm-chatbot-template-cpu/models
```

### 8-2. Hugging Face CLI 사용
`wget` 로 바로 받으려다 **404 / 401 오류**가 발생할 수 있습니다.  
이 경우 `hf download` 를 사용하는 것이 가장 안전합니다.

먼저 설치:

```bash
cd ~/llm-chatbot-template-cpu/fastapi-app
source .venv/bin/activate
python -m pip install -U huggingface_hub
```

모델 다운로드:

```bash
cd ~/llm-chatbot-template-cpu/models

hf download Qwen/Qwen2.5-7B-Instruct-GGUF \
  --include "qwen2.5-7b-instruct-q4_k_m*" \
  --local-dir .
```

### 다운로드 결과 예시
```text
qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf
qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf
```

---

## 9. GGUF split 모델 merge

Qwen GGUF는 **분할 파일**로 받아질 수 있습니다.  
이 경우 단순 `cat` 으로 합치면 안 되고, **llama.cpp 유틸로 merge** 해야 합니다.

```bash
cd ~/llm-chatbot-template-cpu/models

/root/llama.cpp/build/bin/llama-gguf-split --merge \
  qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf \
  qwen2.5-7b-instruct-q4_k_m.gguf
```

### merge 결과 확인
```bash
ls -lh
```

정상 예시:
```text
qwen2.5-7b-instruct-q4_k_m.gguf
```

---

## 10. 환경파일 설정

### 10-1. `.env`
```bash
cd ~/llm-chatbot-template-cpu
vim .env
```

예시:

```env
APP_NAME=fastapi-cpu-chatbot
FASTAPI_HOST=0.0.0.0
FASTAPI_PORT=8000

LLM_ENGINE=llama_cpp
LLM_MODEL_PATH=/root/llm-chatbot-template-cpu/models/qwen2.5-7b-instruct-q4_k_m.gguf
LLM_MAX_TOKENS=512
LLM_CONTEXT_SIZE=4096
LLM_THREADS=8
LLM_TEMPERATURE=0.7

RAG_ENABLED=true
RAG_TOP_K=5
RAG_TOP_K_WIDE=30
```

### 10-2. `.env.db`
```bash
vim .env.db
```

예시:

```env
PGHOST=127.0.0.1
PGPORT=5432
PGDATABASE=game_rag
PGUSER=postgres
PGPASSWORD=password
```

---

## 11. llama.cpp 모델 단독 테스트

```bash
cd ~/llm-chatbot-template-cpu/fastapi-app
source .venv/bin/activate

python3 - <<'PY'
from llama_cpp import Llama

llm = Llama(
    model_path="/root/llm-chatbot-template-cpu/models/qwen2.5-7b-instruct-q4_k_m.gguf",
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

정상이라면 한국어 응답이 나옵니다.

---

## 12. RAG 데이터 준비

### 12-1. 필요한 폴더만 받기
원본 레포에서 `data` 폴더만 받고 싶다면:

```bash
svn export https://github.com/MelodyFrogK/llm-chatbot-template/trunk/data
```

또는 필요한 것만:

```bash
svn export https://github.com/MelodyFrogK/llm-chatbot-template/trunk/data/derived
svn export https://github.com/MelodyFrogK/llm-chatbot-template/trunk/data/sql
```

### 12-2. RAG 입력 파일 확인
적재 스크립트는 아래 파일을 읽습니다.

```text
data/derived/rag_documents_seed.jsonl
```

없으면 직접 생성할 수 있습니다.

예시:

```bash
mkdir -p ~/llm-chatbot-template-cpu/data/derived

cat > ~/llm-chatbot-template-cpu/data/derived/rag_documents_seed.jsonl <<'EOF'
{"id":"doc-001","source":"manual","doc_type":"item","category":"weapon","title":"은빛검","content":"은빛검은 공격력 25, 명중률 12를 가진 희귀 무기이다."}
{"id":"doc-002","source":"manual","doc_type":"item","category":"armor","title":"강철갑옷","content":"강철갑옷은 방어력 40을 제공하는 일반 방어구이다."}
{"id":"doc-003","source":"manual","doc_type":"item","category":"consumable","title":"회복물약","content":"회복물약은 체력을 50 회복시키는 소모품이다."}
{"id":"doc-004","source":"manual","doc_type":"user_inventory","category":"inventory","title":"김택진 보유 아이템","content":"김택진은 은빛검 1개, 회복물약 3개를 보유하고 있다."}
EOF
```

---

## 13. PostgreSQL 테이블 생성

```bash
PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -f data/sql/create_tables.sql
```

또는 DB 접속 후 직접 실행:

```sql
create table if not exists public.items_master (
    item_id      text primary key,
    category     text not null,
    item_name    text not null,
    attack       integer,
    accuracy     integer,
    defense      integer,
    effect       text,
    rarity       text
);

create table if not exists public.user_inventory (
    inventory_id bigserial primary key,
    user_id      text not null,
    user_name    text not null,
    category     text not null,
    item_name    text not null,
    count        integer not null check (count >= 0)
);

create table if not exists public.rag_documents (
    id         text primary key,
    source     text not null,
    doc_type   text not null,
    category   text not null,
    title      text not null,
    content    text not null,
    embedding  cdb_admin.vector(1024)
);
```

---

## 14. RAG 적재 실행

중요:
- 반드시 **레포 루트에서 실행**
- `.env.db` 도 **레포 루트에 있어야 함**
- `rag` 폴더 안에서 `python3 rag/ingest_pgvector.py` 실행하면 경로가 꼬일 수 있음

정상 실행 순서:

```bash
cd ~/llm-chatbot-template-cpu
source ~/llm-chatbot-template-cpu/fastapi-app/.venv/bin/activate
export $(grep -v '^#' ~/llm-chatbot-template-cpu/.env.db | xargs)
python3 rag/ingest_pgvector.py
```

### 적재 확인
```bash
PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "select count(*) from public.rag_documents;"
```

샘플 확인:

```bash
PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "select id, title, category from public.rag_documents limit 10;"
```

---

## 15. FastAPI 실행

```bash
cd ~/llm-chatbot-template-cpu/fastapi-app
source .venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8000
```

### 확인
- Swagger UI: `http://서버IP:8000/docs`
- Health Check: `http://서버IP:8000/health`
- Web UI: `http://서버IP:8000`

---

## 16. API 테스트

### LLM 단독 테스트
```bash
curl -X POST http://127.0.0.1:8000/chat \
-H "Content-Type: application/json" \
-d '{"message":"안녕하세요. 자기소개 해줘.","use_rag":false,"history":[]}'
```

### RAG 테스트
```bash
curl -X POST http://127.0.0.1:8000/chat \
-H "Content-Type: application/json" \
-d '{"message":"은빛검 능력치 알려줘","use_rag":true,"history":[]}'
```

또는

```bash
curl -X POST http://127.0.0.1:8000/chat \
-H "Content-Type: application/json" \
-d '{"message":"김택진이 가진 아이템 알려줘","use_rag":true,"history":[]}'
```

---

## 17. Web UI 테스트

브라우저에서 질문을 입력하고 FastAPI 응답을 받을 수 있습니다.

동작 구조:

```text
Browser → /chat → FastAPI → llama.cpp
Browser → /chat → FastAPI → pgvector → 검색 문서 → llama.cpp
```

현재 Web UI 기능:
- 채팅형 입력/응답
- Enter 전송
- 한글 조합 중복 전송 방지
- 프론트엔드 history 저장 기반 문맥 유지

---

## 18. systemd 서비스 등록

### 서비스 파일 복사
```bash
sudo cp deploy/fastapi.service /etc/systemd/system/fastapi.service
```

### 경로 확인
`deploy/fastapi.service` 안의 경로는 실제 서버 경로와 맞춰야 합니다.

예:
- `WorkingDirectory=/root/llm-chatbot-template-cpu/fastapi-app`
- `EnvironmentFile=/root/llm-chatbot-template-cpu/.env`
- `ExecStart=/root/llm-chatbot-template-cpu/fastapi-app/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000`

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

## 19. 서버 부하 확인 명령어

### 전체 CPU / load
```bash
top
```

또는

```bash
htop
```

설치:
```bash
sudo apt install -y htop
```

### 메모리
```bash
free -h
```

### 코어별 사용률
```bash
mpstat -P ALL 1
```

설치:
```bash
sudo apt install -y sysstat
```

### 프로세스 확인
```bash
ps aux | grep uvicorn
ps aux | grep llama
```

---

## 20. 학생 실습 순서

### Lab 1. Ubuntu 기본 패키지 설치
### Lab 2. 저장소 clone
### Lab 3. Python 가상환경 생성
### Lab 4. llama.cpp 설치
### Lab 5. GGUF 모델 다운로드
### Lab 6. split GGUF merge
### Lab 7. `.env` / `.env.db` 설정
### Lab 8. llama.cpp 단독 테스트
### Lab 9. RAG 데이터 준비
### Lab 10. PostgreSQL 테이블 생성
### Lab 11. RAG 적재 실행
### Lab 12. FastAPI 실행
### Lab 13. `/health`, `/chat` 테스트
### Lab 14. Web UI 테스트
### Lab 15. systemd 등록
### Lab 16. 부하 확인

---

## 21. 자주 발생하는 문제

### 21-1. Hugging Face 다운로드 404 / 401
원인:
- `wget` 직링크 실패
- 저장소 인증/다운로드 방식 문제

해결:
```bash
python -m pip install -U huggingface_hub
hf download Qwen/Qwen2.5-7B-Instruct-GGUF --include "qwen2.5-7b-instruct-q4_k_m*" --local-dir .
```

### 21-2. GGUF split 파일을 `cat` 으로 병합
원인:
- 단순 `cat` 병합은 모델 로딩 실패 가능

해결:
```bash
/root/llama.cpp/build/bin/llama-gguf-split --merge \
  qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf \
  qwen2.5-7b-instruct-q4_k_m.gguf
```

### 21-3. `FileNotFoundError: LLM model file not found`
원인:
- `.env` 의 `LLM_MODEL_PATH` 와 실제 파일 경로 불일치

확인:
```bash
ls -lh ~/llm-chatbot-template-cpu/models
grep LLM_MODEL_PATH ~/llm-chatbot-template-cpu/.env
```

### 21-4. `rag_documents_seed.jsonl` 없음
원인:
- `data/derived/rag_documents_seed.jsonl` 파일이 없음

해결:
- `svn export` 로 `data/derived` 받기
- 또는 직접 JSONL 생성

### 21-5. `python3: can't open file ... rag/rag/ingest_pgvector.py`
원인:
- `rag` 폴더 안에서 다시 `rag/ingest_pgvector.py` 실행

해결:
- 반드시 **레포 루트에서** 실행

```bash
cd ~/llm-chatbot-template-cpu
python3 rag/ingest_pgvector.py
```

### 21-6. `.env.db` 없음
원인:
- 현재 디렉토리 기준으로 `.env.db` 를 찾으려다 실패

해결:
```bash
export $(grep -v '^#' ~/llm-chatbot-template-cpu/.env.db | xargs)
```

### 21-7. `select count(*) ...` 를 bash 에서 직접 입력
원인:
- SQL을 쉘에서 실행

해결:
```bash
PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "select count(*) from public.rag_documents;"
```

### 21-8. 502 Bad Gateway
원인:
- 실제 원인은 FastAPI 내부 예외
- 주로 모델 경로 오류, 모델 merge 오류, RAG 예외

확인:
```bash
journalctl -u fastapi -f
```

### 21-9. `ModuleNotFoundError: No module named 'llama_cpp'`
해결:
```bash
cd ~/llm-chatbot-template-cpu/fastapi-app
source .venv/bin/activate
pip install -r requirements.txt
```

### 21-10. 응답이 너무 느림
권장 시작값:
```env
LLM_CONTEXT_SIZE=4096
LLM_THREADS=8
LLM_MAX_TOKENS=256
```

---

## 22. Git 업로드 시 주의

절대 올리면 안 되는 것:
- `.env`
- `.env.db`
- `.venv`
- `models/*.gguf`

`.gitignore` 예시:

```gitignore
__pycache__/
*.pyc

.venv/
fastapi-app/.venv/

.env
.env.db

models/*.gguf

*.log
.DS_Store
```

---

## 23. OS 버전 다를 경우 레포를 따로 나눠야 하나?

보통은 **레포를 나누지 않습니다.**

일반적인 방식:
- 레포 하나 유지
- `README` 에 Ubuntu / macOS / Docker 절차를 분리
- `scripts/install-ubuntu.sh`, `scripts/install-mac.sh` 같이 분리

레포를 따로 나누는 경우:
- CPU / GPU 구조가 완전히 다를 때
- MLX 버전 / llama.cpp 버전처럼 **추론 엔진 자체가 완전히 다를 때**
- 운영 구조가 크게 다를 때

즉,
- **Ubuntu 22.04 vs 24.04** 정도는 같은 레포에서 관리
- **MLX 버전 vs CPU llama.cpp 버전** 정도면 분리 고려 가능

---

## 24. 운영 방향

권장 구조:

```text
개발/실습:
Ubuntu + FastAPI + llama.cpp + GGUF + PostgreSQL(pgvector)

확장 시:
Nginx + FastAPI + PostgreSQL(pgvector) + 별도 추론 엔진(vLLM 등) 검토
```

즉,
- 학생 실습 / 소규모 배포: **llama.cpp**
- 대규모 운영 / 동시성 증가: **별도 추론 서버** 검토

---

## 25. Git 반영 예시

```bash
git add .
git commit -m "Add Ubuntu CPU + RAG deployment guide"
git push
```
