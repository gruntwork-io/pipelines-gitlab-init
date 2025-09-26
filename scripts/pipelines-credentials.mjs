
import fs from "fs"

const main = async () => {
    try {
        const apiBaseURL = process.env.API_BASE_URL
        const idToken = process.env.APERTURE_OIDC_TOKEN;

        const isRetryableError = (response) => {
            return response.status >= 500 || response.status === 429
        }

        const loginWithRetries = async (tries) => {
            const providerTokenResponse = await fetch(`${apiBaseURL}/tokens/auth/login`, {
                method: "POST",
                headers: {
                    "Authorization": `Bearer ${idToken}`
                }
            })

            if (providerTokenResponse.ok) {
                return providerTokenResponse
            } else {
                if (tries > 0 && isRetryableError(providerTokenResponse)) {
                    console.error(providerTokenResponse)
                    console.log(`Failed to get provider token: ${providerTokenResponse.status} ${providerTokenResponse.statusText}. Retrying...`)

                    // Random backoff between 0 and 3 seconds
                    await new Promise(resolve => setTimeout(resolve, Math.floor(Math.random() * 3000)))

                    return loginWithRetries(tries - 1)
                } else {
                    return providerTokenResponse
                }
            }
        }

        const providerTokenResponse = await loginWithRetries(3)

        if (providerTokenResponse.ok) {
            const providerTokenJson = await providerTokenResponse.json()
            const pipelinesTokenResponse = await fetch(`${apiBaseURL}/tokens/pat/${process.env.PIPELINES_TOKEN_PATH}`, {
                method: "GET",
                headers: {
                    "Authorization": `Bearer ${providerTokenJson.token}`
                }
            })

            if (pipelinesTokenResponse.ok) {
                const pipelinesTokenJson = await pipelinesTokenResponse.json()
                console.log("Outputted pipelines token to build.env")
                // This must be a project relative path to work with GitLab dotenv artifacts
                fs.appendFileSync("credentials.sh", `PIPELINES_GRUNTWORK_READ_TOKEN=${pipelinesTokenJson.token}\n`)
                return
            } else {
                console.error(pipelinesTokenResponse)
                console.log(`Failed to get pipelines token: ${pipelinesTokenResponse.status} ${pipelinesTokenResponse.statusText}`)
                process.exit(1)
            }

        } else {
            console.error(providerTokenResponse)
            console.log(`Failed to get provider token: ${providerTokenResponse.status} ${providerTokenResponse.statusText}`)
            process.exit(1)
        }

    } catch (error) {
        console.log(`Failed to get pipelines token: ${error}`)
        process.exit(1)
    }
}

main()