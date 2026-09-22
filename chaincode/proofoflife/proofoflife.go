package main

import (
	"fmt"
	"os"

	"github.com/hyperledger/fabric-chaincode-go/v2/shim"
	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

// SmartContract is a throwaway chaincode for Phase 2. Its only job is to
// prove the full deploy pipeline (package/install/approve/commit) and a
// real transaction (submit + evaluate) work end to end across 3 orgs.
// Real record chaincode starts in Phase 3.
type SmartContract struct {
	contractapi.Contract
}

// Put writes a key/value pair to world state. This is a "submit" — it goes
// through endorsement, ordering, and creates a new block.
func (s *SmartContract) Put(ctx contractapi.TransactionContextInterface, key string, value string) error {
	return ctx.GetStub().PutState(key, []byte(value))
}

// Get reads a key's current value from world state. This is an
// "evaluate" — it never creates a block, it just reads the peer's local
// copy of world state.
func (s *SmartContract) Get(ctx contractapi.TransactionContextInterface, key string) (string, error) {
	value, err := ctx.GetStub().GetState(key)
	if err != nil {
		return "", fmt.Errorf("failed to read from world state: %w", err)
	}
	if value == nil {
		return "", fmt.Errorf("key %q does not exist", key)
	}
	return string(value), nil
}

// Chaincode-as-a-Service mode: this binary runs as its own long-lived
// container, and the peer connects out to it (CHAINCODE_SERVER_ADDRESS)
// instead of the peer building and starting the container itself. TLS is
// disabled here because this only ever talks to peers over the private
// Docker network created for this project (network/docker-compose-*.yaml),
// never exposed outside it.
func main() {
	chaincode, err := contractapi.NewChaincode(&SmartContract{})
	if err != nil {
		panic(fmt.Sprintf("error creating proofoflife chaincode: %v", err))
	}

	server := &shim.ChaincodeServer{
		CCID:     os.Getenv("CHAINCODE_ID"),
		Address:  os.Getenv("CHAINCODE_SERVER_ADDRESS"),
		CC:       chaincode,
		TLSProps: shim.TLSProperties{Disabled: true},
	}
	if err := server.Start(); err != nil {
		panic(fmt.Sprintf("error starting proofoflife chaincode: %v", err))
	}
}
