package main

import (
	"github.com/google/gopacket"
	"sync"
)

type Send struct {
	packet gopacket.Packet // packet data
	srcif  string          // interface it came in on
}

type SendPktFeed struct {
	lock    sync.Mutex  // lock
	senders []chan Send // list of channels to send packets on
}

// Function to send a packet out all the other interfaces other than srcif
func (s *SendPktFeed) Send(p gopacket.Packet, srcif string) {
	s.lock.Lock()
	for _, send := range s.senders {
		send <- Send{packet: p, srcif: srcif}
	}
	s.lock.Unlock()
}

// Register a channel to recieve packet data we want to send
func (s *SendPktFeed) RegisterSender(send chan Send) {
	s.lock.Lock()
	s.senders = append(s.senders, send)
	s.lock.Unlock()
}
