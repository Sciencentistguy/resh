package histfile

import (
	"encoding/json"
	"log"
	"os"
	"strconv"
	"sync"

	"github.com/curusarn/resh/pkg/histlist"
	"github.com/curusarn/resh/pkg/records"
)

// Histfile writes records to histfile
type Histfile struct {
	sessionsMutex sync.Mutex
	sessions      map[string]records.Record
	historyPath   string

	recentMutex   sync.Mutex
	recentRecords []records.Record

	cmdLines histlist.Histlist
}

// New creates new histfile and runs two gorutines on it
func New(input chan records.Record, historyPath string, initHistSize int, sessionsToDrop chan string,
	signals chan os.Signal, shutdownDone chan string) *Histfile {

	hf := Histfile{
		sessions:    map[string]records.Record{},
		historyPath: historyPath,
		cmdLines:    histlist.New(),
	}
	go hf.loadHistory(initHistSize)
	go hf.writer(input, signals, shutdownDone)
	go hf.sessionGC(sessionsToDrop)
	return &hf
}

func (h *Histfile) loadHistory(initHistSize int) {
	h.recentMutex.Lock()
	defer h.recentMutex.Unlock()
	log.Println("histfile: Loading history from file ...")
	h.cmdLines = records.LoadCmdLinesFromFile(h.historyPath, initHistSize)
	log.Println("histfile: History loaded - cmdLine count:", len(h.cmdLines.List))
}

// sessionGC reads sessionIDs from channel and deletes them from histfile struct
func (h *Histfile) sessionGC(sessionsToDrop chan string) {
	for {
		func() {
			session := <-sessionsToDrop
			log.Println("histfile: got session to drop", session)
			h.sessionsMutex.Lock()
			defer h.sessionsMutex.Unlock()
			if part1, found := h.sessions[session]; found == true {
				log.Println("histfile: Dropping session:", session)
				delete(h.sessions, session)
				go writeRecord(part1, h.historyPath)
			} else {
				log.Println("histfile: No hanging parts for session:", session)
			}
		}()
	}
}

// writer reads records from channel, merges them and writes them to file
func (h *Histfile) writer(input chan records.Record, signals chan os.Signal, shutdownDone chan string) {
	for {
		func() {
			select {
			case record := <-input:
				h.sessionsMutex.Lock()
				defer h.sessionsMutex.Unlock()

				// allows nested sessions to merge records properly
				mergeID := record.SessionID + "_" + strconv.Itoa(record.Shlvl)
				if record.PartOne {
					if _, found := h.sessions[mergeID]; found {
						log.Println("histfile WARN: Got another first part of the records before merging the previous one - overwriting! " +
							"(this happens in bash because bash-preexec runs when it's not supposed to)")
					}
					h.sessions[mergeID] = record
				} else {
					if part1, found := h.sessions[mergeID]; found == false {
						log.Println("histfile ERROR: Got second part of records and nothing to merge it with - ignoring! (mergeID:", mergeID, ")")
					} else {
						delete(h.sessions, mergeID)
						go h.mergeAndWriteRecord(part1, record)
					}
				}
			case sig := <-signals:
				log.Println("histfile: Got signal " + sig.String())
				h.sessionsMutex.Lock()
				defer h.sessionsMutex.Unlock()
				log.Println("histfile DEBUG: Unlocked mutex")

				for sessID, record := range h.sessions {
					log.Panicln("histfile WARN: Writing incomplete record for session " + sessID)
					h.writeRecord(record)
				}
				log.Println("histfile DEBUG: Shutdown success")
				shutdownDone <- "histfile"
				return
			}
		}()
	}
}

func (h *Histfile) writeRecord(part1 records.Record) {
	writeRecord(part1, h.historyPath)
}

func (h *Histfile) mergeAndWriteRecord(part1, part2 records.Record) {
	err := part1.Merge(part2)
	if err != nil {
		log.Println("Error while merging", err)
		return
	}

	func() {
		h.recentMutex.Lock()
		defer h.recentMutex.Unlock()
		h.recentRecords = append(h.recentRecords, part1)
		cmdLine := part1.CmdLine
		idx, found := h.cmdLines.LastIndex[cmdLine]
		if found {
			h.cmdLines.List = append(h.cmdLines.List[:idx], h.cmdLines.List[idx+1:]...)
		}
		h.cmdLines.LastIndex[cmdLine] = len(h.cmdLines.List)
		h.cmdLines.List = append(h.cmdLines.List, cmdLine)
	}()

	writeRecord(part1, h.historyPath)
}

func writeRecord(rec records.Record, outputPath string) {
	recJSON, err := json.Marshal(rec)
	if err != nil {
		log.Println("Marshalling error", err)
		return
	}
	f, err := os.OpenFile(outputPath,
		os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Println("Could not open file", err)
		return
	}
	defer f.Close()
	_, err = f.Write(append(recJSON, []byte("\n")...))
	if err != nil {
		log.Printf("Error while writing: %v, %s\n", rec, err)
		return
	}
}

// GetRecentCmdLines returns recent cmdLines
func (h *Histfile) GetRecentCmdLines(limit int) histlist.Histlist {
	h.recentMutex.Lock()
	defer h.recentMutex.Unlock()
	log.Println("histfile: History requested ...")
	hl := histlist.Copy(h.cmdLines)
	log.Println("histfile: History copied - cmdLine count:", len(hl.List))
	return hl
}
