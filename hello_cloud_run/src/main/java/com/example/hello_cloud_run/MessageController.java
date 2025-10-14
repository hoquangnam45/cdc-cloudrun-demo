package com.example.hello_cloud_run;

import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/messages")
public class MessageController {

    private final MessageRepository messageRepository;

    public MessageController(MessageRepository messageRepository) {
        this.messageRepository = messageRepository;
    }

    @GetMapping
    public List<Message> getAllMessages() {
        return messageRepository.findAll();
    }

    @PostMapping
    public Message createMessage(@RequestBody Message message) {
        return messageRepository.save(message);
    }

    @GetMapping("/{id}")
    public Message getMessageById(@PathVariable Long id) {
        return messageRepository.findById(id).orElse(null);
    }

    @PutMapping("/{id}")
    public Message updateMessage(@PathVariable Long id, @RequestBody Message updatedMessage) {
        return messageRepository.findById(id)
                .map(message -> {
                    message.setContent(updatedMessage.getContent());
                    return messageRepository.save(message);
                })
                .orElse(null);
    }

    @DeleteMapping("/{id}")
    public void deleteMessage(@PathVariable Long id) {
        messageRepository.deleteById(id);
    }
}
