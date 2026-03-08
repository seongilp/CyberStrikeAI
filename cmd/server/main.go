package main

import (
	"cyberstrike-ai/internal/app"
	"cyberstrike-ai/internal/config"
	"cyberstrike-ai/internal/logger"
	"flag"
	"fmt"
)

func main() {
	var configPath = flag.String("config", "config.yaml", "설정 파일 경로")
	flag.Parse()

	// 설정 로드
	cfg, err := config.Load(*configPath)
	if err != nil {
		fmt.Printf("설정 로드 실패: %v\n", err)
		return
	}

	// 로그 초기화
	log := logger.New(cfg.Log.Level, cfg.Log.Output)

	// 애플리케이션 생성
	application, err := app.New(cfg, log)
	if err != nil {
		log.Fatal("애플리케이션 초기화 실패", "error", err)
	}

	// 서버 시작
	if err := application.Run(); err != nil {
		log.Fatal("서버 시작 실패", "error", err)
	}
}

