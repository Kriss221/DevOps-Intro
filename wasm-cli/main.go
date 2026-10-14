package main

import (
	"fmt"
	"os"
	"time"
)

func main() {
	method := os.Getenv("REQUEST_METHOD")
	path := os.Getenv("PATH_INFO")

	if method != "GET" {
		fmt.Fprintln(os.Stderr, "only GET is supported")
		os.Exit(1)
	}

	if path != "/time" {
		fmt.Fprintln(os.Stderr, "unknown path")
		os.Exit(1)
	}

	moscow := time.Now().UTC().Add(3 * time.Hour)

	iso := moscow.Format("2006-01-02T15:04:05") + "+03:00"
	hourMinute := moscow.Format("15:04")

	fmt.Printf(
		"{\"unix\":%d,\"iso\":%q,\"hour_minute\":%q,\"timezone\":\"UTC+3\"}\n",
		moscow.Unix(),
		iso,
		hourMinute,
	)
}
