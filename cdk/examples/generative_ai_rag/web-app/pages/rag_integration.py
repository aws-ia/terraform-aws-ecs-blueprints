import boto3
import streamlit as st
import json
import uuid
from typing import Dict, Any, List, Optional, Generator

# Constants
MODEL_ID = 'anthropic.claude-3-5-sonnet-20240620-v1:0'
KNOWLEDGE_BASE_PARAM = "knowledge_base_id"
MODEL_ARN = f"arn:aws:bedrock:us-west-2::foundation-model/{MODEL_ID}"
INITIAL_MESSAGE = "Hello, Builders! Ask me any questions you have about AWS re:Invent sessions."

# Initialize Streamlit session state
if "messages" not in st.session_state:
    st.session_state["messages"] = [{"role": "assistant", "content": INITIAL_MESSAGE}]
if "session_id" not in st.session_state:
    st.session_state["session_id"] = None

@st.cache_data
def get_parameter(name: str) -> Optional[str]:
    """Retrieve a parameter from AWS Systems Manager Parameter Store."""
    try:
        ssm = boto3.client('ssm')
        param = ssm.get_parameter(Name=name, WithDecryption=True)
        return param['Parameter']['Value']
    except Exception as e:
        st.error(f"Error retrieving parameter: {e}")
        return None

def invoke_bedrock_stream(client: Any, system_prompt: str, user_prompt: str) -> Generator[str, None, None]:
    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 4000,
        "temperature": 0.1,
        "top_p": 0.9,
        "system": system_prompt,
        "messages": [{"role": "user", "content": user_prompt}]
    })

    with st.spinner("Generating response...."):
        try:
            response = client.invoke_model_with_response_stream(
                body=body,
                modelId=MODEL_ID,
                accept='application/json',
                contentType='application/json'
            )
            for event in response.get('body'):
                chunk = json.loads(event['chunk']['bytes'])
                if chunk['type'] == 'content_block_delta':
                    if chunk['delta']['type'] == 'text_delta':
                        yield chunk['delta']['text']
                elif chunk['type'] == 'content_block_stop':
                    break
        except Exception as e:
            st.error(f"Error invoking Bedrock model: {e}")
            yield ""

def get_prompt_template(retrieved_passages: List[str]) -> str:
    """Return the improved prompt template for the AI assistant with response formatting."""
    return f"""
    You are an AI assistant answering questions about AWS re:Invent 2024 session information and general queries.
    Your task is to analyze the user's question, categorize it, and provide an appropriate response.
    Every session information includes the following fields:
    - Title
    - Session Code
    - Description
    - Session Type
    - Topic
    - Areas of Interest
    - Level
    - Target Roles
    - Venue
    - Date and Time
    - Prerequisites
    - Key Points

    First, analyze the user's question and categorize it into one of the following:

    1. GENERAL
        - This question type is for general questions that are not related to re:Invent sessions.

    2. REINVENT_INFORMATION
        - This question type is for questions requesting information about specific sessions
        - This question type is for questions requesting information about sessions held at certain venue and times

    3. REINVENT_RECOMMENDATION
        - This question type is for session recommendation questions for specific topics or interests

    Second, analyze the user's question and provide a response based on the question type.

    1. GENERAL
        - Ignore the content in the retrieved passages.
        - Provide a direct answer to the question based on your general knowledge.
        - Do not include any uncertain information or speculation.
        - If the question is outside your knowledge base, politely state that you don't have that information.

    2. REINVENT_INFORMATION
        - Think step-by-step before providing an answer.
        - Use the information from the retrieved passages to answer the question.
        - Extract all fields data from each information and use it to generate an answer.
        - Prioritize recommendations based on:
            a) Relevance in the "Related AWS Services", "Description" and "Title" fields
            b) Relevance to the "Topic" and "Areas of Interest"
        - When a specific date is mentioned, only recommend sessions occurring on that exact date.

    3. REINVENT_RECOMMENDATION
        - Think step-by-step before providing an answer.
        - Use the information from the retrieved passages to answer the question.
        - Extract all fields data from each information and use it to generate an answer.
        - Analyze each condition of the question one by one, with particular emphasis on matching the exact date and time, and venue.
        - When a specific date or venue is mentioned, only recommend sessions occurring on that exact date and venue.

    Here are the retrieved passages:

    {retrieved_passages}

    IMPORTANT:
    - Always base your answers on the provided data and refrain from offering uncertain information.
    - Your final response should only contain the actual answer to the user's question.
    - Do not include any explanation of your thought process, categorization, or analysis in the final response.
    - If retrieved passages are empty and question type is not GENERAL, respond with "Sorry. I couldn't find any related information."
    - Do not modify fields data in the retrieved passages.
    - If all conditions are not met, recommend similar sessions and be sure to explain the reason.

    CRITICAL RESPONSE FORMAT:
    - You MUST format your entire response EXACTLY as follows, with no exceptions:

    [QUESTION_TYPE]
    GENERAL or REINVENT_RECOMMENDATION or REINVENT_INFORMATION
    [/QUESTION_TYPE]
    [RESPONSE]
    Your complete answer here, with no text outside these tags.
    [/RESPONSE]

    IMPORTANT RESPONSE FORMAT RULES:
    1. ALWAYS include both [QUESTION_TYPE] and [RESPONSE] tags.
    2. [QUESTION_TYPE] must contain ONLY ONE of the three specified types, nothing else.
    3. [RESPONSE] must contain your COMPLETE answer and nothing else.
    4. DO NOT include ANY text outside of these tags.
    5. If you cannot provide an answer, still use the tags and put your "Sorry. I couldn't answer that question." message inside the [RESPONSE] tags.
    6. Never use [GENERAL], [REINVENT_RECOMMENDATION], or [REINVENT_INFORMATION] as standalone tags.

    EXAMPLE OF CORRECT FORMAT:
    [QUESTION_TYPE]
    REINVENT_RECOMMENDATION
    [/QUESTION_TYPE]
    [RESPONSE]
    Based on your question, I recommend the following session:

    1. Responsible generative AI tabletop: Governance and oversight [REPEAT]
        - Session Code: GHJ208-R1
        - Session Type: Gamified learning
        - Venue: Mandalay Bay
        - Date and Time: Wednesday, Dec 04, 12:00 p.m.
        - This session offers a gamified learning experience where participants engage in a tabletop exercise simulating board-level decision-making for generative AI initiatives in a fictional organization. ... (blah, blah) ...
    2. ... (More sessions) ...
    [/RESPONSE]

    Failure to follow this format exactly will result in an error. Double-check your response before submitting.
    """

def retrieve_from_knowledge_base(client: Any, knowledge_base_id: str, prompt: str) -> List[Dict[str, Any]]:
    """Retrieve relevant passages from the knowledge base."""
    with st.spinner("Retrieving relevant information from the knowledge base...."):
        try:
            response = client.retrieve(
                knowledgeBaseId=knowledge_base_id,
                retrievalQuery={
                    'text': prompt
                },
                retrievalConfiguration={
                    'vectorSearchConfiguration': {
                        'numberOfResults': 20
                    }
                }
            )
            return response.get('retrievalResults', [])
        except Exception as e:
            st.error(f"Error retrieving from knowledge base: {e}")
            return []

def main():
    st.title("💬 Chat with Knowledge Base")
    st.caption("Using Amazon Bedrock with RAG integration")

    for msg in st.session_state.messages:
        st.chat_message(msg["role"]).write(msg["content"])

    if prompt := st.chat_input():
        st.chat_message("user").write(prompt)
        st.session_state.messages.append({"role": "user", "content": prompt})

        knowledge_base_id = get_parameter(KNOWLEDGE_BASE_PARAM)
        if not knowledge_base_id:
            st.info("Something is wrong with parameter store")
            st.stop()

        agent_client = boto3.client('bedrock-agent-runtime')
        bedrock_runtime_client = boto3.client('bedrock-runtime')

        try:
            # Retrieve relevant passages from the knowledge base
            retrieved_results = retrieve_from_knowledge_base(agent_client, knowledge_base_id, prompt)

            # Extract and format the retrieved passages
            retrieved_passages = [result['content']['text'] for result in retrieved_results]
            formatted_passages = "\n\n".join(f"Passage {i+1}:\n{passage}" for i, passage in enumerate(retrieved_passages))

            # Initialize variables to store the full response and the content after the [RESPONSE] tag
            full_response = ""
            response_content = ""
            response_started = False

            message_placeholder = st.chat_message("assistant").empty()

            # Generate the final response using the invoke_model API
            system_prompt = get_prompt_template(formatted_passages)

            # Process each chunk from the Bedrock stream
            for chunk in invoke_bedrock_stream(bedrock_runtime_client, system_prompt, prompt):
                # Accumulate the full response
                full_response += chunk

                # Check if we've reached the [RESPONSE] tag
                if '[RESPONSE]' in chunk:
                    response_started = True
                    # Extract the content after the [RESPONSE] tag
                    response_content = chunk.split('[RESPONSE]')[1]
                elif response_started:
                    # If we're past the [RESPONSE] tag, continue accumulating the response content
                    response_content += chunk

                # Display the response content if we've started collecting it
                if response_started:
                    # Remove the [/RESPONSE] tag if present and display the content
                    message_placeholder.markdown(response_content.replace('[/RESPONSE]', '') + "▌")

            # Extract question type and response
            import re
            question_type_match = re.search(r'\[QUESTION_TYPE\](.*?)\[/QUESTION_TYPE\]', full_response, re.DOTALL)
            response_match = re.search(r'\[RESPONSE\](.*?)\[/RESPONSE\]', full_response, re.DOTALL)

            question_type = question_type_match.group(1).strip() if question_type_match else "UNKNOWN"
            final_response = response_match.group(1).strip() if response_match else "I apologize. There was an issue generating an appropriate response."

            message_placeholder.markdown(final_response)

            st.session_state.messages.append({"role": "assistant", "content": final_response})

            # Display citations only for non-general questions
            if question_type not in ["GENERAL", "UNKNOWN"]:
                with st.expander("Data Sources"):
                    for i, result in enumerate(retrieved_results, 1):
                        content = result['content']['text']
                        st.markdown(f"**Source {i}:**")
                        st.text_area(f"Chunk Data {i}", value=content, height=150, disabled=True)
                        st.markdown("---")

        except boto3.exceptions.Boto3Error as e:
            print(f"Boto3 Error: {e}")
            if 'Session with Id' in str(e) and 'is not valid' in str(e):
                st.session_state["session_id"] = str(uuid.uuid4())
                st.warning("Session has expired. Starting a new session. Please enter your question again.")
            else:
                st.error("An error occurred while processing the response. Please check the logs for details.")

            msg = "I encountered an issue while processing the response. Could you please rephrase your prompt or try a different question?"
            st.session_state.messages.append({"role": "assistant", "content": msg})
            st.chat_message("assistant").write(msg)

if __name__ == "__main__":
    main()
