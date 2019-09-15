package main

import (
	"sort"
	"strconv"

	"github.com/curusarn/resh/common"
	"github.com/mb-14/gomarkov"
)

type strategyMarkovChainCmd struct {
	order       int
	history     []strMarkCmdHistoryEntry
	historyCmds []string
}

type strMarkCmdHistoryEntry struct {
	cmd     string
	cmdLine string
}

type strMarkCmdEntry struct {
	cmd       string
	transProb float64
}

func (s *strategyMarkovChainCmd) init() {
	s.history = nil
	s.historyCmds = nil
}

func (s *strategyMarkovChainCmd) GetTitleAndDescription() (string, string) {
	return "command-based markov chain (order " + strconv.Itoa(s.order) + ")", "Use command-based markov chain to recommend commands"
}

func (s *strategyMarkovChainCmd) GetCandidates() []string {
	if len(s.history) < s.order {
		var hist []string
		for _, item := range s.history {
			hist = append(hist, item.cmdLine)
		}
		return hist
	}
	chain := gomarkov.NewChain(s.order)

	chain.Add(s.historyCmds)

	cmdsSet := map[string]bool{}
	var entries []strMarkCmdEntry
	for _, cmd := range s.historyCmds {
		if cmdsSet[cmd] {
			continue
		}
		cmdsSet[cmd] = true
		prob, _ := chain.TransitionProbability(cmd, s.historyCmds[len(s.historyCmds)-s.order:])
		entries = append(entries, strMarkCmdEntry{cmd: cmd, transProb: prob})
	}
	sort.Slice(entries, func(i int, j int) bool { return entries[i].transProb > entries[j].transProb })
	var hist []string
	histSet := map[string]bool{}
	for i := len(s.history) - 1; i >= 0; i-- {
		if histSet[s.history[i].cmdLine] {
			continue
		}
		histSet[s.history[i].cmdLine] = true
		if s.history[i].cmd == entries[0].cmd {
			hist = append(hist, s.history[i].cmdLine)
		}
	}
	// log.Println("################")
	// log.Println(s.history[len(s.history)-s.order:])
	// log.Println(" -> ")
	// x := math.Min(float64(len(hist)), 3)
	// log.Println(entries[:int(x)])
	// x = math.Min(float64(len(hist)), 5)
	// log.Println(hist[:int(x)])
	// log.Println("################")
	return hist
}

func (s *strategyMarkovChainCmd) AddHistoryRecord(record *common.EnrichedRecord) error {
	s.history = append(s.history, strMarkCmdHistoryEntry{cmdLine: record.CmdLine, cmd: record.Command})
	s.historyCmds = append(s.historyCmds, record.Command)
	// s.historySet[record.CmdLine] = true
	return nil
}

func (s *strategyMarkovChainCmd) ResetHistory() error {
	s.init()
	return nil
}
