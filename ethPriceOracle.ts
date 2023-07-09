const axios = require('axios')
const BN = require('bn.js')
const common = require('./utils/common.js')
const SLEEP_INTERVAL = Number(process.env.SLEEP_INTERVAL) || 2000
const PRIVATE_KEY_FILE_NAME = process.env.PRIVATE_KEY_FILE || './oracle/oracle_private_key'
const CHUNK_SIZE = Number(process.env.CHUNK_SIZE) || 3
const MAX_RETRIES = Number(process.env.MAX_RETRIES) || 5
const OracleJSON = require('./oracle/build/contracts/EthPriceOracle.json')

type OracleRequest = {
	callerAddress: any,
	id: any
}

// Naive DB for pending requests between the caller contract and the oracle contract
var pendingRequests: OracleRequest[] = []

// Get an instance of the Oracle contract
/** Starts off a series of actions:
 * connect to Extdev TestNet by calling the common.loadAccount function
 * instantiate the oracle contract
 * start listening for events
 */
async function init() {
	const { ownerAddress, web3js, client } = common.loadAccount(PRIVATE_KEY_FILE_NAME)
	const oracleContract = await getOracleContract(web3js)
	filterEvents(oracleContract, web3js)
	return {
		oracleContract,
		ownerAddress,
		client
	}
}

async function getOracleContract(web3js) {
  const networkId = await web3js.eth.net.getId()
  return new web3js.eth.Contract(OracleJSON.abi, OracleJSON.networks[networkId].address)
}

// Filter out events to listen to on the Oracle contract
async function filterEvents(oracleContract, web3js) {
    oracleContract.events.GetLatestEthPriceEvent(async (err, event) => {
        if (err) {
            console.error('Error on event', err)
            return
        }
        await addRequestToQueue(event)
    })
    oracleContract.events.SetLatestEthPriceEvent(async (err, event) => {
        if (err) {
            console.error('Error on event', err)
            return
        }
				// Do something...
    })
}

// Push event values into pendingRequests as a new OracleRequest type, FIFO
async function addRequestToQueue(event) {
  const {callerAddress, id} = event.returnValues
	const oracleRequest: OracleRequest = { callerAddress, id }
  pendingRequests.push(oracleRequest)
}

// Process the pending requests in chunks
// Continue processing until queue is empty, FIFO
async function processQueue(oracleContract, ownerAddress) {
  let processedRequests = 0
  while (pendingRequests.length > 0 && processedRequests < CHUNK_SIZE) {
    const req = pendingRequests.shift()
    await processRequest(oracleContract, ownerAddress, req?.id, req?.callerAddress)
    processedRequests++
  }
}

// Process the request with a retry mechanism
// Make HTTP request to Binance API to get the latest ETH price
// If fails, retry again. If failed MAX_RETRIES, then alert the caller contract cannot get oracle price.
// Quickest way to do this is to set the ETH price to zero, indicating a failed response and N/A state
async function processRequest(oracleContract, ownerAddress, id, callerAddress) {
	  let retries = 0
    while (retries < MAX_RETRIES) {
        try {
					// Make HTTP request to Binance API
					const ethPrice = await retrieveLatestEthPrice()
					await setLatestEthPrice(oracleContract, callerAddress, ownerAddress, ethPrice, id)
					return
        } catch (error) {
            // Request failed
						if (retries === MAX_RETRIES - 1) {
							// Set to zero
							await setLatestEthPrice(oracleContract, callerAddress, ownerAddress, '0', id)
							return
						}
						// Retry
						retries++
        }
    }
}

// Gets the latest ETH price from Binance API via an HTTP request, use within a try/catch
async function retrieveLatestEthPrice() {
	const resp = await axios({
    url: 'https://api.binance.com/api/v3/ticker/price',
    params: {
      symbol: 'ETHUSDT'
    },
    method: 'get'
  })
  return resp.data.price
}

// Sets the latest eth price on the oracle contract
async function setLatestEthPrice(oracleContract, callerAddress, ownerAddress, ethPrice, id) {
	const multiplier = new BN(10**10, 10) // since api returns with 8 decimals
  const ethPriceInt = (new BN(parseInt(ethPrice.replace(".", "")), 10)).mul(multiplier)
  const idInt = new BN(parseInt(id))
  try {
    await oracleContract.methods.setLatestEthPrice(ethPriceInt.toString(), callerAddress, idInt.toString()).send({ from: ownerAddress })
  } catch (error) {
    console.log('Error encountered while calling setLatestEthPrice.')
    // Do some error handling
  }
}

/**
 * Process the queue in batches on an interval
 * Due to JavaScript's single-threaded nature, process the queue in batches and the thread will sleep for SLEEP_INTERVAL between each iteration
 */
(async () => {
	const { oracleContract, ownerAddress, client } = await init()
  process.on( 'SIGINT', () => {
		// Gracefully shut down the oracle
    console.log('Shutting down the oracle client')
		client.disconnect()
    process.exit()
  })
  setInterval(async () => {
    await processQueue(oracleContract, ownerAddress)
  }, SLEEP_INTERVAL)
})()