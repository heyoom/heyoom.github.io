.PHONY: help sync full push deploy server stop logs restart build clean

# 기본 타겟
.DEFAULT_GOAL := help

# 변수
HUGO_SESSION := hugo_server
SYNC_SCRIPT := ./sync-obsidian.sh

help: ## 사용 가능한 명령어 표시
	@echo "MoyoRun 블로그 관리 명령어:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""

sync: ## 증분 sync (변경된 파일만)
	$(SYNC_SCRIPT)

full: ## 전체 sync (모든 파일 재생성)
	$(SYNC_SCRIPT) --full

push: ## 증분 sync + git push
	$(SYNC_SCRIPT) --push

deploy: ## 전체 sync + git push (배포)
	$(SYNC_SCRIPT) --full --push

server: ## Hugo 서버 시작 (tmux)
	@if tmux has-session -t $(HUGO_SESSION) 2>/dev/null; then \
		echo "✓ Hugo 서버가 이미 실행 중입니다"; \
		echo "  로그: make logs"; \
		echo "  중지: make stop"; \
	else \
		tmux new-session -d -s $(HUGO_SESSION); \
		tmux send-keys -t $(HUGO_SESSION) "hugo server -D" C-m; \
		sleep 1; \
		echo "✓ Hugo 서버 시작: http://localhost:1313"; \
		echo "  로그: make logs"; \
		echo "  중지: make stop"; \
	fi

stop: ## Hugo 서버 중지
	@if tmux has-session -t $(HUGO_SESSION) 2>/dev/null; then \
		tmux kill-session -t $(HUGO_SESSION); \
		echo "✓ Hugo 서버 중지됨"; \
	else \
		echo "✗ Hugo 서버가 실행 중이 아닙니다"; \
	fi

logs: ## Hugo 서버 로그 확인
	@if tmux has-session -t $(HUGO_SESSION) 2>/dev/null; then \
		tmux capture-pane -t $(HUGO_SESSION) -p -S -100; \
	else \
		echo "✗ Hugo 서버가 실행 중이 아닙니다"; \
		echo "  시작: make server"; \
	fi

restart: stop server ## Hugo 서버 재시작

build: ## Hugo 빌드 (프로덕션)
	hugo --minify

clean: ## 빌드 파일 삭제
	rm -rf public resources
	@echo "✓ 빌드 파일 삭제 완료"
