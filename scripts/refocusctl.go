package main

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"time"
)

const socketPath = "/tmp/refocus.sock"

type StatusResponse struct {
	Mode                 string       `json:"mode"`
	MenuTitle            string       `json:"menuTitle"`
	StatusLine           string       `json:"statusLine"`
	HardModeEnabled      bool         `json:"hardModeEnabled"`
	WorkSecondsRemaining *int         `json:"workSecondsRemaining"`
	RecentTabs           []RecentTab  `json:"recentTabs"`
}

type RecentTab struct {
	Host      string  `json:"host"`
	URL       string  `json:"url"`
	Timestamp float64 `json:"timestamp"`
}

func formatTime(seconds *int) string {
	if seconds == nil {
		return "--:--"
	}
	s := *seconds
	if s < 0 {
		s = 0
	}
	return fmt.Sprintf("%02d:%02d", s/60, s%60)
}

func requestStatus() (*StatusResponse, error) {
	conn, err := net.DialTimeout("unix", socketPath, 5*time.Second)
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	conn.SetDeadline(time.Now().Add(5 * time.Second))

	_, err = conn.Write([]byte(`{"type":"CLI_STATUS"}` + "\n"))
	if err != nil {
		return nil, err
	}

	// Half-close to signal done writing
	if uc, ok := conn.(*net.UnixConn); ok {
		uc.CloseWrite()
	}

	buf := make([]byte, 8192)
	n, err := conn.Read(buf)
	if err != nil {
		return nil, err
	}

	var status StatusResponse
	if err := json.Unmarshal(buf[:n], &status); err != nil {
		return nil, err
	}

	return &status, nil
}

func cmdStatus(jsonOutput bool) {
	status, err := requestStatus()
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Fprintln(os.Stderr, "Refocus socket not found; is the app running?")
		} else {
			fmt.Fprintf(os.Stderr, "Failed to query Refocus: %v\n", err)
		}
		os.Exit(1)
	}

	if jsonOutput {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		enc.Encode(status)
		return
	}

	hardMode := "off"
	if status.HardModeEnabled {
		hardMode = "on"
	}

	fmt.Printf("Mode: %s (hard mode %s)\n", status.Mode, hardMode)
	fmt.Printf("Status: %s\n", status.StatusLine)
	fmt.Printf("Time remaining: %s\n", formatTime(status.WorkSecondsRemaining))

	if len(status.RecentTabs) > 0 {
		fmt.Println("Recent tabs:")
		for _, tab := range status.RecentTabs {
			fmt.Printf("  - %s  (%s)\n", tab.Host, tab.URL)
		}
	}
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: refocusctl <command>")
		fmt.Println("Commands:")
		fmt.Println("  status [--json]  Show current Refocus state")
		os.Exit(0)
	}

	switch os.Args[1] {
	case "status":
		jsonOutput := len(os.Args) > 2 && os.Args[2] == "--json"
		cmdStatus(jsonOutput)
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", os.Args[1])
		os.Exit(1)
	}
}
