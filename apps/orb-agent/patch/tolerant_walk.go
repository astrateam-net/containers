package snmp

import (
	"sort"
	"strconv"
	"strings"

	"github.com/gosnmp/gosnmp"
)

// tolerantWalkAll walks rootOid tolerating non-increasing OIDs (RouterOS
// BRIDGE-MIB quirk), like `snmpwalk -Cc`. Drop-in for gosnmp's strict WalkAll.
func tolerantWalkAll(client *gosnmp.GoSNMP, rootOid string) ([]gosnmp.SnmpPDU, error) {
	const maxReps = 20
	useBulk := client.Version != gosnmp.Version1

	getNext := func(cursor string) ([]gosnmp.SnmpPDU, error) {
		if useBulk {
			resp, err := client.GetBulk([]string{cursor}, 0, maxReps)
			if err != nil {
				return nil, err
			}
			return resp.Variables, nil
		}
		resp, err := client.GetNext([]string{cursor})
		if err != nil {
			return nil, err
		}
		return resp.Variables, nil
	}

	return tolerantWalk(rootOid, getNext)
}

// tolerantWalk is the transport-independent loop (split out for unit tests).
// getNext returns the varbind(s) after cursor and must not enforce increasing OIDs.
func tolerantWalk(rootOid string, getNext func(cursor string) ([]gosnmp.SnmpPDU, error)) ([]gosnmp.SnmpPDU, error) {
	root := strings.TrimPrefix(rootOid, ".")
	prefix := root + "."

	seen := make(map[string]struct{})
	out := make([]gosnmp.SnmpPDU, 0)
	cursor := rootOid

	for {
		vars, err := getNext(cursor)
		if err != nil {
			return out, err
		}
		if len(vars) == 0 {
			break
		}

		added := 0
		done := false
		for _, v := range vars {
			if v.Type == gosnmp.EndOfMibView || v.Type == gosnmp.NoSuchObject || v.Type == gosnmp.NoSuchInstance {
				done = true
				break
			}
			name := strings.TrimPrefix(v.Name, ".")
			if name != root && !strings.HasPrefix(name, prefix) {
				done = true // left the subtree
				break
			}
			if _, dup := seen[name]; !dup {
				seen[name] = struct{}{}
				out = append(out, v)
				added++
			}
			cursor = v.Name // advance even on dup, so a non-increasing device progresses
		}

		if done || added == 0 { // added == 0: nothing new -> loop protection
			break
		}
	}

	sort.Slice(out, func(i, j int) bool { return lessOID(out[i].Name, out[j].Name) })
	return out, nil
}

// lessOID orders dotted OIDs numerically per component (110 > 9, unlike strings).
func lessOID(a, b string) bool {
	as := strings.Split(strings.TrimPrefix(a, "."), ".")
	bs := strings.Split(strings.TrimPrefix(b, "."), ".")
	for i := 0; i < len(as) && i < len(bs); i++ {
		ai, aerr := strconv.Atoi(as[i])
		bi, berr := strconv.Atoi(bs[i])
		if aerr != nil || berr != nil {
			if as[i] != bs[i] {
				return as[i] < bs[i]
			}
			continue
		}
		if ai != bi {
			return ai < bi
		}
	}
	return len(as) < len(bs)
}
