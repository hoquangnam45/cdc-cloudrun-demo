package com.example.quarkus_cloud_run;

import io.quarkus.hibernate.orm.panache.PanacheEntity;
import jakarta.persistence.Entity;

@Entity
public class Message extends PanacheEntity {
    public String content;
}