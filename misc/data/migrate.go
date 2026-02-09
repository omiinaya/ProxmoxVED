// +build ignore

// Migration script to import data from the old API to PocketBase
// Run with: go run migrate.go
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

const (
	defaultSourceAPI = "https://api.htl-braunau.at/dev/data"
	defaultPBURL     = "http://localhost:8090"
	batchSize        = 100
)

var (
	sourceAPI  string
	summaryAPI string
)

// OldDataModel represents the data structure from the old API
type OldDataModel struct {
	ID         string `json:"id"`
	CtType     int    `json:"ct_type"`
	DiskSize   int    `json:"disk_size"`
	CoreCount  int    `json:"core_count"`
	RamSize    int    `json:"ram_size"`
	OsType     string `json:"os_type"`
	OsVersion  string `json:"os_version"`
	DisableIP6 string `json:"disableip6"`
	NsApp      string `json:"nsapp"`
	Method     string `json:"method"`
	CreatedAt  string `json:"created_at"`
	PveVersion string `json:"pve_version"`
	Status     string `json:"status"`
	RandomID   string `json:"random_id"`
	Type       string `json:"type"`
	Error      string `json:"error"`
}

// PBRecord represents the PocketBase record format
type PBRecord struct {
	CtType     int    `json:"ct_type"`
	DiskSize   int    `json:"disk_size"`
	CoreCount  int    `json:"core_count"`
	RamSize    int    `json:"ram_size"`
	OsType     string `json:"os_type"`
	OsVersion  string `json:"os_version"`
	DisableIP6 string `json:"disableip6"`
	NsApp      string `json:"nsapp"`
	Method     string `json:"method"`
	PveVersion string `json:"pve_version"`
	Status     string `json:"status"`
	RandomID   string `json:"random_id"`
	Type       string `json:"type"`
	Error      string `json:"error"`
	// created_at will be set automatically by PocketBase
}

type Summary struct {
	TotalEntries int `json:"total_entries"`
}

func main() {
	// Setup source URLs
	baseURL := os.Getenv("MIGRATION_SOURCE_URL")
	if baseURL == "" {
		baseURL = defaultSourceAPI
	}
	sourceAPI = baseURL + "/paginated"
	summaryAPI = baseURL + "/summary"

	pbURL := os.Getenv("POCKETBASE_URL")
	if pbURL == "" {
		pbURL = defaultPBURL
	}

	pbCollection := os.Getenv("POCKETBASE_COLLECTION")
	if pbCollection == "" {
		pbCollection = "_dev_telemetry_data"
	}

	fmt.Println("===========================================")
	fmt.Println("   Data Migration to PocketBase")
	fmt.Println("===========================================")
	fmt.Printf("Source API:       %s\n", baseURL)
	fmt.Printf("PocketBase URL:   %s\n", pbURL)
	fmt.Printf("Collection:       %s\n", pbCollection)
	fmt.Println("-------------------------------------------")

	// Get total count
	summary, err := getSummary()
	if err != nil {
		fmt.Printf("❌ Failed to get summary: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("📊 Total entries to migrate: %d\n", summary.TotalEntries)
	fmt.Println("-------------------------------------------")

	// Calculate pages
	totalPages := (summary.TotalEntries + batchSize - 1) / batchSize

	var totalMigrated, totalFailed, totalSkipped int

	for page := 1; page <= totalPages; page++ {
		fmt.Printf("📦 Fetching page %d/%d (items %d-%d)...\n",
			page, totalPages,
			(page-1)*batchSize+1,
			min(page*batchSize, summary.TotalEntries))

		data, err := fetchPage(page, batchSize)
		if err != nil {
			fmt.Printf("   ❌ Failed to fetch page %d: %v\n", page, err)
			totalFailed += batchSize
			continue
		}

		for i, record := range data {
			err := importRecord(pbURL, pbCollection, record)
			if err != nil {
				if isUniqueViolation(err) {
					totalSkipped++
					continue
				}
				fmt.Printf("   ❌ Failed to import record %d: %v\n", (page-1)*batchSize+i+1, err)
				totalFailed++
				continue
			}
			totalMigrated++
		}

		fmt.Printf("   ✅ Page %d complete (migrated: %d, skipped: %d, failed: %d)\n",
			page, len(data), totalSkipped, totalFailed)

		// Small delay to avoid overwhelming the server
		time.Sleep(100 * time.Millisecond)
	}

	fmt.Println("===========================================")
	fmt.Println("   Migration Complete")
	fmt.Println("===========================================")
	fmt.Printf("✅ Successfully migrated: %d\n", totalMigrated)
	fmt.Printf("⏭️  Skipped (duplicates):  %d\n", totalSkipped)
	fmt.Printf("❌ Failed:                 %d\n", totalFailed)
	fmt.Println("===========================================")
}

func getSummary() (*Summary, error) {
	resp, err := http.Get(summaryAPI)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var summary Summary
	if err := json.NewDecoder(resp.Body).Decode(&summary); err != nil {
		return nil, err
	}

	return &summary, nil
}

func fetchPage(page, limit int) ([]OldDataModel, error) {
	url := fmt.Sprintf("%s?page=%d&limit=%d", sourceAPI, page, limit)

	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(body))
	}

	var data []OldDataModel
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return nil, err
	}

	return data, nil
}

func importRecord(pbURL, collection string, old OldDataModel) error {
	record := PBRecord{
		CtType:     old.CtType,
		DiskSize:   old.DiskSize,
		CoreCount:  old.CoreCount,
		RamSize:    old.RamSize,
		OsType:     old.OsType,
		OsVersion:  old.OsVersion,
		DisableIP6: old.DisableIP6,
		NsApp:      old.NsApp,
		Method:     old.Method,
		PveVersion: old.PveVersion,
		Status:     old.Status,
		RandomID:   old.RandomID,
		Type:       old.Type,
		Error:      old.Error,
	}

	jsonData, err := json.Marshal(record)
	if err != nil {
		return err
	}

	url := fmt.Sprintf("%s/api/collections/%s/records", pbURL, collection)
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(body))
	}

	return nil
}

func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	errStr := err.Error()
	return contains(errStr, "UNIQUE constraint failed") ||
		contains(errStr, "duplicate") ||
		contains(errStr, "already exists")
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsHelper(s, substr))
}

func containsHelper(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
