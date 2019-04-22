class Blockchain {
    private let storage: IStorage
    private let blockValidator: IBlockValidator
    private let factory: IFactory
    weak var listener: IBlockchainDataListener?

    init(storage: IStorage, blockValidator: IBlockValidator, factory: IFactory, listener: IBlockchainDataListener? = nil) {
        self.storage = storage
        self.blockValidator = blockValidator
        self.factory = factory
        self.listener = listener
    }

}

extension Blockchain: IBlockchain {

    func connect(merkleBlock: MerkleBlock) throws -> Block {
        if let existingBlock = storage.block(byHash: merkleBlock.headerHash) {
            return existingBlock
        }

        guard let previousBlock = storage.block(byHash: merkleBlock.header.previousBlockHeaderHash) else {
            throw BitcoinCoreErrors.BlockValidation.noPreviousBlock
        }

        // Validate and chain new blocks
        let block = factory.block(withHeader: merkleBlock.header, previousBlock: previousBlock)
        try blockValidator.validate(block: block, previousBlock: previousBlock)
        block.stale = true

        try storage.add(block: block)
        listener?.onInsert(block: block)

        return block
    }

    func forceAdd(merkleBlock: MerkleBlock, height: Int) throws -> Block {
        let block = factory.block(withHeader: merkleBlock.header, height: height)
        try storage.add(block: block)

        listener?.onInsert(block: block)

        return block
    }

    func handleFork() throws {
        guard let firstStaleHeight = storage.block(stale: true, sortedHeight: "ASC")?.height else {
            return
        }

        let lastNotStaleHeight = storage.block(stale: false, sortedHeight: "DESC")?.height ?? 0

        if (firstStaleHeight <= lastNotStaleHeight) {
            let lastStaleHeight = storage.block(stale: true, sortedHeight: "DESC")?.height ?? firstStaleHeight

            if (lastStaleHeight > lastNotStaleHeight) {
                let notStaleBlocks = storage.blocks(heightGreaterThanOrEqualTo: firstStaleHeight, stale: false)
                try deleteBlocks(blocks: notStaleBlocks)
                try storage.unstaleAllBlocks()
            } else {
                let staleBlocks = storage.blocks(stale: true)
                try deleteBlocks(blocks: staleBlocks)
            }
        } else {
            try storage.unstaleAllBlocks()
        }
    }

    func deleteBlocks(blocks: [Block]) throws {
        let hashes =  blocks.reduce(into: [String](), { acc, block in
            acc.append(contentsOf: storage.transactions(ofBlock: block).map { $0.dataHash.reversedHex })
        })

        try storage.delete(blocks: blocks)
        listener?.onDelete(transactionHashes: hashes)
    }

}
