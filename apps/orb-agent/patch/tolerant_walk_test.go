package snmp

import (
	"errors"
	"testing"

	"github.com/gosnmp/gosnmp"
)

const bridgePortBase = ".1.3.6.1.2.1.17.1.4.1.2"

// realRouterOSChain: exact GETNEXT order captured live from a MikroTik CRS326
// (RouterOS 7.22.3) for dot1dBasePortIfIndex. Strict WalkAll aborts at 125->108;
// we must collect all 16.
var realRouterOSChain = []int{
	107, 125, 108, 122, 109, 123, 110, 124,
	111, 127, 113, 129, 119, 126, 121, 128,
}

// scriptedDevice models a device by its GETNEXT successor map.
type scriptedDevice struct {
	succ    map[string]string
	leaveAt string
}

func newRouterOSDevice() *scriptedDevice {
	succ := map[string]string{}
	prev := bridgePortBase
	for _, idx := range realRouterOSChain {
		cur := bridgePortBase + "." + itoa(idx)
		succ[prev] = cur
		prev = cur
	}
	leave := ".1.3.6.1.2.1.17.1.4.1.3.1"
	succ[prev] = leave
	return &scriptedDevice{succ: succ, leaveAt: leave}
}

// getNextOne simulates single-varbind GETNEXT.
func (d *scriptedDevice) getNextOne(cursor string) ([]gosnmp.SnmpPDU, error) {
	n, ok := d.succ[cursor]
	if !ok {
		return []gosnmp.SnmpPDU{{Name: cursor, Type: gosnmp.EndOfMibView}}, nil
	}
	return []gosnmp.SnmpPDU{{Name: n, Type: gosnmp.Integer, Value: 1}}, nil
}

// getBulkAll simulates one GETBULK returning the whole remaining chain at once.
func (d *scriptedDevice) getBulkAll(cursor string) ([]gosnmp.SnmpPDU, error) {
	var out []gosnmp.SnmpPDU
	for {
		n, ok := d.succ[cursor]
		if !ok {
			break
		}
		out = append(out, gosnmp.SnmpPDU{Name: n, Type: gosnmp.Integer, Value: 1})
		cursor = n
		if n == d.leaveAt {
			break
		}
	}
	return out, nil
}

func TestTolerantWalk_CollectsFullRouterOSChain_GetNext(t *testing.T) {
	got, err := tolerantWalk(bridgePortBase, newRouterOSDevice().getNextOne)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertBridgePorts(t, got)
}

func TestTolerantWalk_CollectsFullRouterOSChain_GetBulk(t *testing.T) {
	got, err := tolerantWalk(bridgePortBase, newRouterOSDevice().getBulkAll)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	assertBridgePorts(t, got)
}

// assertBridgePorts: exactly 16 rows, sorted numeric ascending, none out-of-subtree.
func assertBridgePorts(t *testing.T, got []gosnmp.SnmpPDU) {
	t.Helper()
	want := []int{107, 108, 109, 110, 111, 113, 119, 121, 122, 123, 124, 125, 126, 127, 128, 129}
	if len(got) != len(want) {
		t.Fatalf("row count: got %d, want %d", len(got), len(want))
	}
	for i, pdu := range got {
		wantOID := bridgePortBase + "." + itoa(want[i])
		if pdu.Name != wantOID {
			t.Errorf("row %d: got %s, want %s (not numerically sorted)", i, pdu.Name, wantOID)
		}
	}
}

func TestTolerantWalk_LoopProtection(t *testing.T) {
	// GETNEXT cycles a->b->a...; dedup on seen OIDs must terminate the walk.
	a := bridgePortBase + ".1"
	b := bridgePortBase + ".2"
	cyclic := func(cursor string) ([]gosnmp.SnmpPDU, error) {
		if cursor == bridgePortBase || cursor == b {
			return []gosnmp.SnmpPDU{{Name: a, Type: gosnmp.Integer, Value: 1}}, nil
		}
		return []gosnmp.SnmpPDU{{Name: b, Type: gosnmp.Integer, Value: 1}}, nil
	}
	got, err := tolerantWalk(bridgePortBase, cyclic)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("loop protection: got %d rows, want 2", len(got))
	}
}

func TestTolerantWalk_PropagatesTransportError(t *testing.T) {
	boom := errors.New("connection refused")
	got, err := tolerantWalk(bridgePortBase, func(string) ([]gosnmp.SnmpPDU, error) {
		return nil, boom
	})
	if !errors.Is(err, boom) {
		t.Fatalf("want transport error propagated, got %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("want no rows on immediate error, got %d", len(got))
	}
}

func TestLessOID(t *testing.T) {
	cases := []struct {
		a, b string
		want bool
	}{
		{".1.3.6.1.2.1.17.1.4.1.2.9", ".1.3.6.1.2.1.17.1.4.1.2.110", true},
		{".1.3.6.1.2.1.17.1.4.1.2.125", ".1.3.6.1.2.1.17.1.4.1.2.108", false},
		{"1.3.6.1", "1.3.6.1.1", true},
		{".1.2.3", "1.2.3", false},
	}
	for _, c := range cases {
		if got := lessOID(c.a, c.b); got != c.want {
			t.Errorf("lessOID(%q,%q)=%v want %v", c.a, c.b, got, c.want)
		}
	}
}

// itoa avoids importing strconv just for the test fixtures.
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[i:])
}
