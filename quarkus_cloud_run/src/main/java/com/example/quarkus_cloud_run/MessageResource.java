package com.example.quarkus_cloud_run;

import jakarta.transaction.Transactional;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import java.util.List;

@Path("/messages")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class MessageResource {

    @GET
    public List<Message> getAllMessages() {
        return Message.listAll();
    }

    @POST
    @Transactional
    public Message createMessage(Message message) {
        message.persist();
        return message;
    }

    @GET
    @Path("/{id}")
    public Message getMessageById(@PathParam("id") Long id) {
        return Message.findById(id);
    }

    @PUT
    @Path("/{id}")
    @Transactional
    public Message updateMessage(@PathParam("id") Long id, Message updatedMessage) {
        Message message = Message.findById(id);
        if (message != null) {
            message.content = updatedMessage.content;
            message.persist();
        }
        return message;
    }

    @DELETE
    @Path("/{id}")
    @Transactional
    public void deleteMessage(@PathParam("id") Long id) {
        Message.deleteById(id);
    }
}
