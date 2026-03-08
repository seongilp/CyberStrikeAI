package i18n

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

var (
	mu       sync.RWMutex
	cnMap    = map[string]string{}
	koMap    = map[string]string{}
	language = "cn"
)

// Init loads message property files from the given directory and sets the active language.
// It always loads message_cn.properties as the fallback, and optionally loads
// message_ko.properties when language is "ko".
func Init(messagesDir, lang string) error {
	mu.Lock()
	defer mu.Unlock()

	if lang == "" {
		lang = "cn"
	}
	language = lang

	// Always load CN as fallback
	cnPath := filepath.Join(messagesDir, "message_cn.properties")
	loaded, err := loadProperties(cnPath)
	if err != nil {
		return fmt.Errorf("load message_cn.properties: %w", err)
	}
	cnMap = loaded

	// Load KO if requested
	koMap = map[string]string{}
	if lang == "ko" {
		koPath := filepath.Join(messagesDir, "message_ko.properties")
		loadedKO, err := loadProperties(koPath)
		if err == nil {
			koMap = loadedKO
		}
		// Missing KO file is not fatal — falls back to CN
	}

	return nil
}

// T returns the translated string for the given key.
// Lookup order: ko → cn → key itself.
// Positional placeholders {0}, {1}, … are replaced with args.
func T(key string, args ...interface{}) string {
	mu.RLock()
	defer mu.RUnlock()

	msg := ""
	if language == "ko" {
		if v, ok := koMap[key]; ok {
			msg = v
		}
	}
	if msg == "" {
		if v, ok := cnMap[key]; ok {
			msg = v
		}
	}
	if msg == "" {
		msg = key
	}

	for i, arg := range args {
		placeholder := fmt.Sprintf("{%d}", i)
		msg = strings.ReplaceAll(msg, placeholder, fmt.Sprintf("%v", arg))
	}
	return msg
}

// Lang returns the currently active language code.
func Lang() string {
	mu.RLock()
	defer mu.RUnlock()
	return language
}

// TemplateMap returns a read-only copy of the merged translation map
// (ko values override cn) suitable for JSON serialisation and injection
// into HTML templates.
func TemplateMap() map[string]string {
	mu.RLock()
	defer mu.RUnlock()

	out := make(map[string]string, len(cnMap)+len(koMap))
	for k, v := range cnMap {
		out[k] = v
	}
	if language == "ko" {
		for k, v := range koMap {
			out[k] = v
		}
	}
	return out
}

// loadProperties parses a Java-style .properties file.
// Lines starting with '#' are treated as comments; blank lines are skipped.
// Only the first '=' on a line separates key from value.
func loadProperties(path string) (map[string]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	m := map[string]string{}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		idx := strings.IndexByte(line, '=')
		if idx < 0 {
			continue
		}
		key := strings.TrimSpace(line[:idx])
		val := strings.TrimSpace(line[idx+1:])
		if key != "" {
			m[key] = val
		}
	}
	return m, scanner.Err()
}
