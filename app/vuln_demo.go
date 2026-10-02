package main

import "golang.org/x/text/language"

func vulnerableDependencyDemo() {
	_, _ = language.Parse("en")
}
